// Check Grafana via Cloudflare tunnel for refresh loop
const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');

puppeteer.use(StealthPlugin());

const GRAFANA_URL = 'https://grafanarr.thomker.net';
const CF_ACCESS_CLIENT_ID = '1471b986dcb9d987341259b568c0be6c.access';
const CF_ACCESS_CLIENT_SECRET = '1182c48f380416e651cf6e8078682f6f04fb766cff8ce246130898a31fa3efab';

async function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function checkGrafanaTunnel() {
    console.log('Checking Grafana via Cloudflare tunnel...');
    console.log(`URL: ${GRAFANA_URL}`);

    const browser = await puppeteer.launch({
        headless: false,
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--window-size=1600,1000']
    });

    const page = await browser.newPage();
    await page.setViewport({ width: 1600, height: 1000 });

    // Set Cloudflare Access headers
    await page.setExtraHTTPHeaders({
        'CF-Access-Client-Id': CF_ACCESS_CLIENT_ID,
        'CF-Access-Client-Secret': CF_ACCESS_CLIENT_SECRET
    });

    // Track reloads
    let reloadCount = 0;
    let navigationLog = [];

    page.on('load', () => {
        reloadCount++;
        const url = page.url();
        navigationLog.push({ count: reloadCount, url, time: new Date().toISOString() });
        console.log(`Page load #${reloadCount}: ${url}`);
    });

    page.on('console', msg => {
        if (msg.type() === 'error') {
            console.log('Console error:', msg.text());
        }
    });

    try {
        console.log('\nNavigating to Grafana tunnel...');
        await page.goto(GRAFANA_URL, { waitUntil: 'networkidle2', timeout: 60000 });

        await sleep(2000);
        await page.screenshot({ path: 'C:/git/DockArr-Stack/grafana-tunnel-initial.png', fullPage: true });

        const title = await page.title();
        const url = page.url();
        console.log('Title:', title);
        console.log('URL:', url);

        // Check if we're on login page
        if (url.includes('/login')) {
            console.log('\nLogging in...');
            const usernameInput = await page.$('input[name="user"]');
            const passwordInput = await page.$('input[type="password"]');

            if (usernameInput && passwordInput) {
                await usernameInput.type('admin');
                await passwordInput.type('admin');
                const loginBtn = await page.$('button[type="submit"]');
                if (loginBtn) await loginBtn.click();
                await sleep(5000);
            }
        }

        await page.screenshot({ path: 'C:/git/DockArr-Stack/grafana-tunnel-after-login.png', fullPage: true });

        // Observe for 20 seconds
        console.log('\nObserving for 20 seconds...');
        const initialCount = reloadCount;

        for (let i = 0; i < 20; i++) {
            await sleep(1000);
            process.stdout.write('.');
        }
        console.log('');

        if (reloadCount > initialCount + 2) {
            console.log(`\n⚠️ REFRESH LOOP DETECTED: ${reloadCount - initialCount} reloads in 20 seconds`);
            console.log('Navigation log:');
            navigationLog.slice(-10).forEach(n => console.log(`  ${n.count}: ${n.url}`));
        } else {
            console.log('\n✓ No refresh loop detected');
        }

        await page.screenshot({ path: 'C:/git/DockArr-Stack/grafana-tunnel-final.png', fullPage: true });

        console.log('\n=== Final State ===');
        console.log('URL:', page.url());
        console.log('Title:', await page.title());

    } catch (error) {
        console.error('Error:', error.message);
        await page.screenshot({ path: 'C:/git/DockArr-Stack/grafana-tunnel-error.png' });
    } finally {
        console.log('\nKeeping browser open for 5 seconds...');
        await sleep(5000);
        await browser.close();
    }
}

checkGrafanaTunnel().then(() => process.exit(0));
