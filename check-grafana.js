// Verify Grafana home dashboard
const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');

puppeteer.use(StealthPlugin());

const GRAFANA_URL = 'http://10.0.1.204:3000';

async function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function checkGrafana() {
    console.log('Verifying Grafana home dashboard...');

    const browser = await puppeteer.launch({
        headless: false,
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--window-size=1600,1000']
    });

    const page = await browser.newPage();
    await page.setViewport({ width: 1600, height: 1000 });

    try {
        // Login
        await page.goto(GRAFANA_URL + '/login', { waitUntil: 'networkidle2' });
        await sleep(1000);

        const usernameInput = await page.$('input[name="user"]');
        const passwordInput = await page.$('input[type="password"]');

        if (usernameInput && passwordInput) {
            await usernameInput.type('admin');
            await passwordInput.type('admin');
            const loginBtn = await page.$('button[type="submit"]');
            if (loginBtn) await loginBtn.click();
            await sleep(3000);
        }

        // Go to home
        await page.goto(GRAFANA_URL + '/', { waitUntil: 'networkidle2' });
        await sleep(3000);

        const url = page.url();
        const title = await page.title();
        console.log('URL:', url);
        console.log('Title:', title);

        await page.screenshot({ path: 'C:/git/DockArr-Stack/grafana-home-dashboard.png', fullPage: true });
        console.log('Screenshot saved: grafana-home-dashboard.png');

        // Check if we're on the cAdvisor dashboard
        if (url.includes('pMEd7m0Mz') || title.includes('Cadvisor')) {
            console.log('✓ cAdvisor dashboard is set as home');
        } else {
            console.log('Current page:', title);
        }

    } catch (error) {
        console.error('Error:', error.message);
    } finally {
        await sleep(3000);
        await browser.close();
    }
}

checkGrafana().then(() => process.exit(0));
