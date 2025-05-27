const net = require('net');
const fs = require('fs');
const path = require('path');
const { setTimeout: sleep } = require('timers/promises');
const { getExchangeDetails } = require('tardis-dev');

// 配置
const CONFIG = {
    refreshInterval: 500 * 1000,
    socketDir: path.join(__dirname, 'exchange'), // 使用绝对路径
    timeout: 3000,
    retry: 3
};

class SymbolServer {
    constructor() {
        this.symbolData = new Map(); // exchange -> { lastUpdated, symbols }
        this.servers = new Map();    // exchange -> net.Server
        this.isUpdating = false;
        this.updateInterval = null;
        this.locks = new Map();      // exchange -> { resolve, promise }

        // 确保socket目录存在
        if (!fs.existsSync(CONFIG.socketDir)) {
            console.log('Creating socket directory:', CONFIG.socketDir);
            fs.mkdirSync(CONFIG.socketDir, { recursive: true, mode: 0o755 });
            console.log('Socket directory created with permissions:',
                fs.statSync(CONFIG.socketDir).mode.toString(8));
        }
    }

    async start() {
        try {
            // 清理旧的socket文件（只清理不在当前注册列表中的）
            console.log('Cleaning up old socket files...');
            const files = fs.readdirSync(CONFIG.socketDir);
            const registeredExchanges = Array.from(this.symbolData.keys());

            for (const file of files) {
                if (file.endsWith('.sock')) {
                    const exchange = file.replace('.sock', '');
                    if (!registeredExchanges.includes(exchange)) {
                        const filePath = path.join(CONFIG.socketDir, file);
                        try {
                            fs.unlinkSync(filePath);
                            console.log(`Removed old socket file: ${filePath}`);
                        } catch (err) {
                            console.error(`Failed to remove ${filePath}:`, err);
                        }
                    }
                }
            }

            // 初始加载数据
            await this.updateAllSymbols();

            // 启动定时更新
            this.updateInterval = setInterval(
                () => this.updateAllSymbols(),
                CONFIG.refreshInterval
            );

            console.log('Symbol server started');
        } catch (err) {
            console.error('Failed to start server:', err);
            throw err;
        }
    }

    async stop() {
        clearInterval(this.updateInterval);

        // 关闭所有socket服务器
        for (const [exchange, server] of this.servers) {
            try {
                server.close();
                const socketPath = this.getSocketPath(exchange);
                if (fs.existsSync(socketPath)) {
                    fs.unlinkSync(socketPath);
                }
            } catch (err) {
                console.error(`Failed to cleanup ${exchange}:`, err);
            }
        }

        console.log('Symbol server stopped');
    }

    getSocketPath(exchange) {
        const socketPath = path.join(CONFIG.socketDir, `${exchange}.sock`);
        console.log(`Socket path for ${exchange}:`, socketPath);
        console.log(`Directory exists: ${fs.existsSync(path.dirname(socketPath))}`);
        if (fs.existsSync(path.dirname(socketPath))) {
            console.log(`Directory permissions: ${fs.statSync(path.dirname(socketPath)).mode.toString(8)}`);
        }
        return socketPath;
    }

    async updateSymbols(exchange) {
        // 获取锁
        if (this.locks.has(exchange)) {
            console.log(`Waiting for ${exchange} update to complete...`);
            await this.locks.get(exchange).promise;
            return true;
        }

        let resolve;
        const promise = new Promise(r => resolve = r);
        this.locks.set(exchange, { resolve, promise });

        try {
            console.log(`Updating symbols for ${exchange}...`);
            const result = await this.fetchWithRetry(exchange);

            const filtered = result.availableSymbols
                .filter(s => !s.availableTo)
                .map(s => ({ symbol_id: s.id, type: s.type }));

            // 原子更新
            this.symbolData.set(exchange, {
                lastUpdated: new Date().toISOString(),
                symbols: filtered
            });

            console.log(`Updated ${exchange} with ${filtered.length} symbols`);
            return true;
        } catch (err) {
            console.error(`Failed to update ${exchange}:`, err);
            return false;
        } finally {
            // 释放锁
            const lock = this.locks.get(exchange);
            if (lock) {
                lock.resolve();
                this.locks.delete(exchange);
            }
        }
    }

    async updateAllSymbols() {
        if (this.isUpdating) {
            console.log('Update already in progress, skipping...');
            return;
        }
        this.isUpdating = true;

        try {
            console.log('Starting symbol update...');
            const exchanges = Array.from(this.symbolData.keys());

            // 并行更新所有交易所
            const results = await Promise.all(
                exchanges.map(ex => this.updateSymbols(ex))
            );

            console.log(`Update completed. Success: ${results.filter(Boolean).length}/${exchanges.length}`);
        } catch (err) {
            console.error('Update failed:', err);
        } finally {
            this.isUpdating = false;
        }
    }

    async fetchWithRetry(exchange, attempt = 1) {
        try {
            console.log(`Fetching ${exchange} (attempt ${attempt})...`);
            const controller = new AbortController();
            const timeout = setTimeout(() => controller.abort(), CONFIG.timeout);

            const details = await Promise.race([
                getExchangeDetails(exchange),
                new Promise((_, reject) =>
                    setTimeout(() => reject(new Error('Timeout')), CONFIG.timeout)
                )
            ]);

            clearTimeout(timeout);
            return details;
        } catch (err) {
            if (attempt >= CONFIG.retry) {
                console.error(`Failed to fetch ${exchange} after ${attempt} attempts:`, err);
                throw err;
            }
            console.log(`Retrying ${exchange} (attempt ${attempt + 1})...`);
            await sleep(1000 * attempt);
            return this.fetchWithRetry(exchange, attempt + 1);
        }
    }

    createServer(exchange) {
        const socketPath = this.getSocketPath(exchange);
        console.log(`Creating server for ${exchange} at ${socketPath}`);

        // 确保旧的socket文件被删除
        if (fs.existsSync(socketPath)) {
            try {
                console.log(`Removing existing socket file: ${socketPath}`);
                fs.unlinkSync(socketPath);
                console.log(`Successfully removed old socket file`);
            } catch (err) {
                console.error(`Failed to remove old socket for ${exchange}:`, err);
                throw err; // 抛出错误，让上层处理
            }
        }

        const server = net.createServer(async socket => {
            console.log(`[${exchange}] New client connected`);
            try {
                // 等待更新完成（如果有的话）
                const lock = this.locks.get(exchange);
                if (lock) {
                    console.log(`[${exchange}] Waiting for update to complete...`);
                    await lock.promise;
                }

                const data = this.symbolData.get(exchange);
                if (!data) {
                    console.log(`[${exchange}] No data available`);
                    socket.end(JSON.stringify({ error: 'Exchange not available' }));
                    return;
                }

                console.log(`[${exchange}] Sending data (${data.symbols.length} symbols)`);
                socket.write(JSON.stringify(data));
                socket.end();
                console.log(`[${exchange}] Data sent successfully`);

            } catch (err) {
                console.error(`[${exchange}] Error handling request:`, err);
                socket.end(JSON.stringify({ error: err.message }));
            }
        });

        server.on('error', err => {
            console.error(`[${exchange}] Server error:`, err);
            // 检查socket文件是否存在
            if (fs.existsSync(socketPath)) {
                console.log(`[${exchange}] Socket file exists after error`);
                try {
                    const stats = fs.statSync(socketPath);
                    console.log(`[${exchange}] Socket file stats:`, {
                        size: stats.size,
                        mode: stats.mode.toString(8),
                        uid: stats.uid,
                        gid: stats.gid
                    });
                } catch (statErr) {
                    console.error(`[${exchange}] Failed to stat socket file:`, statErr);
                }
            } else {
                console.error(`[${exchange}] Socket file does not exist after error`);
            }
        });

        server.on('listening', () => {
            console.log(`[${exchange}] Server is listening on ${socketPath}`);
            // 检查socket文件是否存在
            if (fs.existsSync(socketPath)) {
                console.log(`[${exchange}] Socket file exists`);
                try {
                    const stats = fs.statSync(socketPath);
                    console.log(`[${exchange}] Socket file stats:`, {
                        size: stats.size,
                        mode: stats.mode.toString(8),
                        uid: stats.uid,
                        gid: stats.gid
                    });
                } catch (err) {
                    console.error(`[${exchange}] Failed to stat socket file:`, err);
                }
            } else {
                console.error(`[${exchange}] Socket file does not exist after server started listening!`);
            }
        });

        try {
            server.listen(socketPath, () => {
                console.log(`[${exchange}] Server listening on ${socketPath}`);
                // 设置socket文件权限
                try {
                    if (fs.existsSync(socketPath)) {
                        fs.chmodSync(socketPath, 0o666);
                        console.log(`[${exchange}] Socket permissions set to 666`);
                    } else {
                        console.error(`[${exchange}] Socket file does not exist after server started listening!`);
                    }
                } catch (err) {
                    console.error(`[${exchange}] Failed to set socket permissions:`, err);
                }
            });
        } catch (err) {
            console.error(`[${exchange}] Failed to start server:`, err);
            throw err;
        }

        return server;
    }

    async registerExchange(exchange) {
        if (this.symbolData.has(exchange)) {
            console.log(`${exchange} already registered`);
            return;
        }

        console.log(`Registering ${exchange}...`);
        // 初始化数据
        this.symbolData.set(exchange, {
            lastUpdated: null,
            symbols: []
        });

        // 创建socket服务器
        const server = this.createServer(exchange);
        this.servers.set(exchange, server);

        // 立即更新数据
        await this.updateSymbols(exchange);
    }
}

// 使用示例
async function main() {
    const server = new SymbolServer();

    try {
        // 注册要支持的交易所
        const exchanges = ['bitmex',
            'deribit',
            'binance-futures',
            'binance-delivery',
            'binance-options',
            'binance-european-options',
            'binance',
            'ftx',
            'okex-futures',
            'okex-options',
            'okex-swap',
            'okex',
            'okex-spreads',
            'huobi-dm',
            'huobi-dm-swap',
            'huobi-dm-linear-swap',
            'huobi',
            'bitfinex-derivatives',
            'bitfinex',
            'coinbase',
            'coinbase-international',
            'cryptofacilities',
            'kraken',
            'bitstamp',
            'gemini',
            'poloniex',
            'bybit',
            'bybit-spot',
            'bybit-options',
            'phemex',
            'delta',
            'ftx-us',
            'binance-us',
            'gate-io-futures',
            'gate-io',
            'okcoin',
            'bitflyer',
            'hitbtc',
            'coinflex',
            'binance-jersey',
            'binance-dex',
            'upbit',
            'ascendex',
            'dydx',
            'dydx-v4',
            'serum',
            'mango',
            'huobi-dm-options',
            'star-atlas',
            'crypto-com',
            'crypto-com-derivatives',
            'kucoin',
            'kucoin-futures',
            'bitnomial',
            'woo-x',
            'blockchain-com',
            'bitget',
            'bitget-futures',
            'hyperliquid'];
        await Promise.all(exchanges.map(ex => server.registerExchange(ex)));

        // 启动服务器
        await server.start();

        // 处理退出信号
        process.on('SIGINT', async () => {
            console.log('Received SIGINT, shutting down...');
            await server.stop();
            process.exit(0);
        });

        process.on('SIGTERM', async () => {
            console.log('Received SIGTERM, shutting down...');
            await server.stop();
            process.exit(0);
        });
    } catch (err) {
        console.error('Failed to start server:', err);
        process.exit(1);
    }
}

main().catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
});