/**
 * Claude Puppeteer Browser Tool
 * Location: ~/.claude/tools/puppeteer/
 *
 * Usage: node browse.js <command> [options]
 *
 * Commands:
 *   screenshot <url> [output]    - Take screenshot of URL
 *   pdf <url> [output]           - Save page as PDF
 *   html <url>                   - Get page HTML
 *   text <url>                   - Get page text content
 *   eval <url> <script>          - Run JS on page and return result
 *   click <url> <selector>       - Click element and screenshot result
 *   fill <url> <json>            - Fill form fields (JSON: {"selector": "value"})
 *
 * Options:
 *   --headless                   - Run in headless mode (default: true)
 *   --no-headless                - Show browser window
 *   --wait <ms>                  - Wait time after page load (default: 1000)
 *   --width <px>                 - Viewport width (default: 1280)
 *   --height <px>                - Viewport height (default: 800)
 */

const puppeteer = require('puppeteer');

const args = process.argv.slice(2);
const command = args[0];

// Parse options
const options = {
  headless: !args.includes('--no-headless'),
  wait: parseInt(args.find((a, i) => args[i-1] === '--wait') || '1000'),
  width: parseInt(args.find((a, i) => args[i-1] === '--width') || '1280'),
  height: parseInt(args.find((a, i) => args[i-1] === '--height') || '800'),
};

// Filter out option flags to get positional args
const positionalArgs = args.filter((a, i) =>
  !a.startsWith('--') && args[i-1] !== '--wait' && args[i-1] !== '--width' && args[i-1] !== '--height'
);

async function main() {
  if (!command || command === '--help' || command === '-h') {
    console.log(`
Claude Puppeteer Browser Tool

Usage: node browse.js <command> [options]

Commands:
  screenshot <url> [output]    - Take screenshot of URL (default: screenshot.png)
  pdf <url> [output]           - Save page as PDF (default: page.pdf)
  html <url>                   - Get page HTML
  text <url>                   - Get page text content
  title <url>                  - Get page title
  eval <url> <script>          - Run JS on page and return result
  click <url> <selector>       - Click element and screenshot result
  fill <url> <json>            - Fill form fields (JSON: {"selector": "value"})

Options:
  --no-headless                - Show browser window (default: headless)
  --wait <ms>                  - Wait after page load (default: 1000)
  --width <px>                 - Viewport width (default: 1280)
  --height <px>                - Viewport height (default: 800)

Examples:
  node browse.js screenshot https://example.com
  node browse.js screenshot https://example.com output.png --no-headless
  node browse.js text https://example.com
  node browse.js eval https://example.com "document.title"
  node browse.js fill https://example.com '{"#username": "test", "#password": "pass"}'
`);
    process.exit(0);
  }

  const browser = await puppeteer.launch({
    headless: options.headless,
    defaultViewport: { width: options.width, height: options.height }
  });

  const page = await browser.newPage();

  try {
    const url = positionalArgs[1];

    if (!url) {
      console.error('Error: URL required');
      process.exit(1);
    }

    console.error(`Navigating to ${url}...`);
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await new Promise(r => setTimeout(r, options.wait));

    switch (command) {
      case 'screenshot': {
        const output = positionalArgs[2] || 'screenshot.png';
        await page.screenshot({ path: output, fullPage: true });
        console.log(`Screenshot saved: ${output}`);
        break;
      }

      case 'pdf': {
        const output = positionalArgs[2] || 'page.pdf';
        await page.pdf({ path: output, format: 'A4' });
        console.log(`PDF saved: ${output}`);
        break;
      }

      case 'html': {
        const html = await page.content();
        console.log(html);
        break;
      }

      case 'text': {
        const text = await page.evaluate(() => document.body.innerText);
        console.log(text);
        break;
      }

      case 'title': {
        const title = await page.title();
        console.log(title);
        break;
      }

      case 'eval': {
        const script = positionalArgs[2];
        if (!script) {
          console.error('Error: Script required');
          process.exit(1);
        }
        const result = await page.evaluate(script);
        console.log(JSON.stringify(result, null, 2));
        break;
      }

      case 'click': {
        const selector = positionalArgs[2];
        if (!selector) {
          console.error('Error: Selector required');
          process.exit(1);
        }
        await page.click(selector);
        await new Promise(r => setTimeout(r, options.wait));
        await page.screenshot({ path: 'after-click.png' });
        console.log('Clicked element, screenshot saved: after-click.png');
        break;
      }

      case 'fill': {
        const json = positionalArgs[2];
        if (!json) {
          console.error('Error: JSON field map required');
          process.exit(1);
        }
        const fields = JSON.parse(json);
        for (const [selector, value] of Object.entries(fields)) {
          await page.type(selector, value);
          console.error(`Filled ${selector}`);
        }
        await page.screenshot({ path: 'after-fill.png' });
        console.log('Form filled, screenshot saved: after-fill.png');
        break;
      }

      default:
        console.error(`Unknown command: ${command}`);
        process.exit(1);
    }

  } catch (error) {
    console.error(`Error: ${error.message}`);
    await page.screenshot({ path: 'error.png' });
    console.error('Error screenshot saved: error.png');
    process.exit(1);
  } finally {
    await browser.close();
  }
}

main();
