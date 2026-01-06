// DockArr Stack - Web Service Health Test using Puppeteer
// Uses puppeteer-extra with stealth plugin for Cloudflare bypass
// Supports both localhost and Cloudflare tunnel testing with service tokens

const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');

// Apply stealth plugin to avoid bot detection
puppeteer.use(StealthPlugin());

// Cloudflare Access service token credentials
const CF_ACCESS_CLIENT_ID = '1471b986dcb9d987341259b568c0be6c.access';
const CF_ACCESS_CLIENT_SECRET = '1182c48f380416e651cf6e8078682f6f04fb766cff8ce246130898a31fa3efab';

// Service definitions - localhost and tunnel URLs
const services = {
  localhost: [
    { name: 'Sonarr', url: 'http://localhost:8989', expectedTitle: 'Sonarr' },
    { name: 'Radarr', url: 'http://localhost:7878', expectedTitle: 'Radarr' },
    { name: 'Prowlarr', url: 'http://localhost:9696', expectedTitle: 'Prowlarr' },
    { name: 'Bazarr', url: 'http://localhost:6767', expectedTitle: 'Bazarr' },
    { name: 'Jellyseerr', url: 'http://localhost:5055', expectedTitle: null },
    { name: 'Tautulli', url: 'http://localhost:8181', expectedTitle: 'Tautulli' },
    { name: 'RDTClient', url: 'http://localhost:6500', expectedTitle: null },
    { name: 'Tdarr', url: 'http://localhost:8265', expectedTitle: 'Tdarr' },
    { name: 'FlareSolverr', url: 'http://localhost:8191', expectedText: 'FlareSolverr' },
    { name: 'Uptime Kuma', url: 'http://localhost:3001', expectedTitle: null },
    { name: 'Glances', url: 'http://localhost:61208', expectedTitle: 'Glances' },
    { name: 'Grafana', url: 'http://localhost:3000', expectedTitle: 'Grafana' },
    { name: 'Prometheus', url: 'http://localhost:9090', expectedText: 'Prometheus' },
    { name: 'cAdvisor', url: 'http://localhost:8080', expectedTitle: 'cAdvisor' },
  ],
  tunnel: [
    { name: 'DockArr (arr.thomker.net)', url: 'https://arr.thomker.net', expectedTitle: null },
    { name: 'Grafanarr', url: 'https://grafanarr.thomker.net', expectedTitle: 'Grafana' },
    { name: 'Jellyseerr', url: 'https://seerr.thomker.net', expectedTitle: null },
    { name: 'Tdarr', url: 'https://tdarr.thomker.net', expectedTitle: 'Tdarr' },
    { name: 'Uptime Kuma', url: 'https://uptime.thomker.net', expectedTitle: null },
  ]
};

async function testService(browser, service, useCfHeaders = false) {
  const page = await browser.newPage();
  const result = {
    name: service.name,
    url: service.url,
    success: false,
    statusCode: null,
    loadTime: null,
    error: null,
    title: null,
    bodyPreview: null
  };

  try {
    // Set Cloudflare Access headers if testing tunnel
    if (useCfHeaders) {
      await page.setExtraHTTPHeaders({
        'CF-Access-Client-Id': CF_ACCESS_CLIENT_ID,
        'CF-Access-Client-Secret': CF_ACCESS_CLIENT_SECRET
      });
    }

    const startTime = Date.now();

    // Navigate with reasonable timeout
    page.setDefaultTimeout(30000);
    const response = await page.goto(service.url, {
      waitUntil: 'networkidle2',
      timeout: 30000
    });

    result.loadTime = Date.now() - startTime;
    result.statusCode = response ? response.status() : null;
    result.title = await page.title();

    // Get body text preview
    const bodyText = await page.evaluate(() => document.body.innerText.substring(0, 200));
    result.bodyPreview = bodyText.replace(/\s+/g, ' ').trim();

    // Determine success based on criteria
    if (result.statusCode >= 200 && result.statusCode < 400) {
      if (service.expectedTitle && !result.title.toLowerCase().includes(service.expectedTitle.toLowerCase())) {
        result.error = `Expected title containing "${service.expectedTitle}", got "${result.title}"`;
      } else if (service.expectedText && !bodyText.includes(service.expectedText)) {
        result.error = `Expected text "${service.expectedText}" not found`;
      } else {
        result.success = true;
      }
    } else {
      result.error = `HTTP ${result.statusCode}`;
    }

    // Check for Cloudflare challenge page
    if (result.title.includes('Just a moment') || result.title.includes('Attention Required')) {
      result.success = false;
      result.error = 'Cloudflare challenge detected';
    }

  } catch (error) {
    result.error = error.message.substring(0, 100);
  } finally {
    await page.close();
  }

  return result;
}

async function runTests(mode = 'both') {
  console.log('='.repeat(70));
  console.log('DockArr Stack - Web Service Health Check (Puppeteer + Stealth)');
  console.log('='.repeat(70));
  console.log(`Mode: ${mode}`);
  console.log(`Time: ${new Date().toISOString()}\n`);

  const browser = await puppeteer.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-blink-features=AutomationControlled'
    ]
  });

  const allResults = [];

  // Test localhost services
  if (mode === 'localhost' || mode === 'both') {
    console.log('\n--- LOCALHOST TESTS ---\n');
    for (const service of services.localhost) {
      process.stdout.write(`Testing ${service.name.padEnd(20)}... `);
      const result = await testService(browser, service, false);
      allResults.push({ ...result, mode: 'localhost' });

      if (result.success) {
        console.log(`\x1b[32mOK\x1b[0m (${result.loadTime}ms, ${result.statusCode})`);
      } else {
        console.log(`\x1b[31mFAIL\x1b[0m - ${result.error}`);
      }
    }
  }

  // Test tunnel services with CF Access headers
  if (mode === 'tunnel' || mode === 'both') {
    console.log('\n--- CLOUDFLARE TUNNEL TESTS (with Service Token) ---\n');
    for (const service of services.tunnel) {
      process.stdout.write(`Testing ${service.name.padEnd(30)}... `);
      const result = await testService(browser, service, true);
      allResults.push({ ...result, mode: 'tunnel' });

      if (result.success) {
        console.log(`\x1b[32mOK\x1b[0m (${result.loadTime}ms, ${result.statusCode})`);
      } else {
        console.log(`\x1b[31mFAIL\x1b[0m - ${result.error}`);
      }
    }
  }

  await browser.close();

  // Summary
  console.log('\n' + '='.repeat(70));
  console.log('SUMMARY');
  console.log('='.repeat(70));

  const localhostResults = allResults.filter(r => r.mode === 'localhost');
  const tunnelResults = allResults.filter(r => r.mode === 'tunnel');

  if (localhostResults.length > 0) {
    const localhostPassed = localhostResults.filter(r => r.success).length;
    console.log(`\nLocalhost: ${localhostPassed}/${localhostResults.length} passed`);
  }

  if (tunnelResults.length > 0) {
    const tunnelPassed = tunnelResults.filter(r => r.success).length;
    console.log(`Tunnel:    ${tunnelPassed}/${tunnelResults.length} passed`);
  }

  const failed = allResults.filter(r => !r.success);
  if (failed.length > 0) {
    console.log('\n\x1b[31mFailed Services:\x1b[0m');
    failed.forEach(r => {
      console.log(`  - [${r.mode}] ${r.name}: ${r.error}`);
    });
  }

  // Return exit code
  return failed.length > 0 ? 1 : 0;
}

// Parse command line args
const args = process.argv.slice(2);
let mode = 'both';

if (args.includes('--localhost') || args.includes('-l')) {
  mode = 'localhost';
} else if (args.includes('--tunnel') || args.includes('-t')) {
  mode = 'tunnel';
}

if (args.includes('--help') || args.includes('-h')) {
  console.log(`
Usage: node test-dockarr-services.js [options]

Options:
  --localhost, -l    Test only localhost services
  --tunnel, -t       Test only Cloudflare tunnel services
  --help, -h         Show this help

By default, tests both localhost and tunnel services.
`);
  process.exit(0);
}

runTests(mode)
  .then(exitCode => process.exit(exitCode))
  .catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
  });
