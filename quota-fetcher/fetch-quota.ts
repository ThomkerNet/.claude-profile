#!/usr/bin/env bun
/**
 * Claude.ai Quota Fetcher
 *
 * Fetches usage quota from claude.ai using a persistent browser session.
 * First run: Opens visible browser for login
 * Subsequent runs: Headless, reuses session
 *
 * Usage:
 *   bun run fetch-quota.ts          # Normal run (headless if session exists)
 *   bun run fetch-quota.ts --login  # Force visible browser for re-login
 */

import puppeteer, { Browser, Page } from 'puppeteer';
import { existsSync, mkdirSync, writeFileSync, readFileSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';

const CLAUDE_HOME = join(homedir(), '.claude');
const USER_DATA_DIR = join(CLAUDE_HOME, 'quota-browser');
const CACHE_FILE = join(CLAUDE_HOME, '.quota-cache');
const USAGE_URL = 'https://claude.ai/settings/usage';

interface UsageSection {
  percent: number;
  resetTime: string;
}

interface QuotaData {
  fetchedAt: string;
  status: 'ok' | 'auth_required' | 'error';
  session?: UsageSection;
  weekly?: UsageSection;
  sonnet?: UsageSection;
  error?: string;
}

async function writeCache(data: QuotaData) {
  writeFileSync(CACHE_FILE, JSON.stringify(data, null, 2));
  console.log(`Cache written to ${CACHE_FILE}`);
}

async function hasExistingSession(): Promise<boolean> {
  const cookiesPath = join(USER_DATA_DIR, 'Default', 'Cookies');
  return existsSync(cookiesPath);
}

async function fetchQuota(forceLogin = false): Promise<QuotaData> {
  // Ensure user data directory exists
  if (!existsSync(USER_DATA_DIR)) {
    mkdirSync(USER_DATA_DIR, { recursive: true });
  }

  const hasSession = await hasExistingSession();
  const headless = hasSession && !forceLogin;

  console.log(`Session exists: ${hasSession}, Running headless: ${headless}`);

  let browser: Browser | null = null;

  try {
    // Use system Chrome instead of bundled Chromium for better macOS compatibility
    const chromeExecutable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

    browser = await puppeteer.launch({
      headless: headless ? 'new' : false,
      userDataDir: USER_DATA_DIR,
      executablePath: chromeExecutable,
      protocolTimeout: 600000, // 10 min protocol timeout
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-blink-features=AutomationControlled',
      ],
      defaultViewport: { width: 1200, height: 800 },
    });

    const page = await browser.newPage();

    // Set a realistic user agent
    await page.setUserAgent(
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    );

    console.log(`Navigating to ${USAGE_URL}...`);
    await page.goto(USAGE_URL, { waitUntil: 'networkidle2', timeout: 60000 });

    // Check if we hit Cloudflare challenge
    const pageContent = await page.content();
    if (pageContent.includes('Verify you are human') || pageContent.includes('cf-challenge')) {
      console.log('Cloudflare challenge detected, waiting for resolution...');

      if (headless) {
        // Need to switch to visible mode
        await browser.close();
        return fetchQuota(true); // Retry with visible browser
      }

      // Wait for user to complete challenge
      await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 120000 });
    }

    // Check if we're on login page
    const currentUrl = page.url();
    if (currentUrl.includes('/login') || currentUrl.includes('/signin')) {
      console.log('Login required. Please log in to claude.ai...');

      if (headless) {
        await browser.close();
        return fetchQuota(true); // Retry with visible browser
      }

      // Wait for user to log in and navigate to usage page
      console.log('Waiting for login completion...');
      await page.waitForFunction(
        () => window.location.href.includes('/settings/usage'),
        { timeout: 300000 } // 5 minutes for login
      );
    }

    // Wait for usage content to load
    console.log('Waiting for usage data to load...');
    await page.waitForSelector('body', { timeout: 30000 });

    // Give the page a moment to render dynamic content
    await new Promise(resolve => setTimeout(resolve, 3000));

    // Extract usage data - parse the claude.ai usage page structure
    const usageData = await page.evaluate(() => {
      const body = document.body.innerText;

      // Get all text content for debugging
      const debugText = body.substring(0, 2500);

      // Parse the specific format from claude.ai:
      // "Current session" section: "Resets in X hr Y min" + "X% used"
      // "Weekly limits" section: "All models" + "Sonnet only"

      const result = {
        session: { percent: 0, resetTime: '' },
        weekly: { percent: 0, resetTime: '' },
        sonnet: { percent: 0, resetTime: '' },
        debugText,
        url: window.location.href,
      };

      // Match "Resets in X hr Y min" followed by "X% used"
      const sessionMatch = body.match(/Current session[\s\S]*?Resets in ([^\n]+)[\s\S]*?(\d+)% used/i);
      if (sessionMatch) {
        result.session.resetTime = sessionMatch[1].trim();
        result.session.percent = parseInt(sessionMatch[2], 10);
      }

      // Match "All models" section
      const weeklyMatch = body.match(/All models[\s\S]*?Resets ([^\n]+)[\s\S]*?(\d+)% used/i);
      if (weeklyMatch) {
        result.weekly.resetTime = weeklyMatch[1].trim();
        result.weekly.percent = parseInt(weeklyMatch[2], 10);
      }

      // Match "Sonnet only" section
      const sonnetMatch = body.match(/Sonnet only[\s\S]*?Resets ([^\n]+)[\s\S]*?(\d+)% used/i);
      if (sonnetMatch) {
        result.sonnet.resetTime = sonnetMatch[1].trim();
        result.sonnet.percent = parseInt(sonnetMatch[2], 10);
      }

      return result;
    });

    console.log('Extracted data:', JSON.stringify(usageData, null, 2));

    // Take a screenshot for debugging
    const screenshotPath = join(CLAUDE_HOME, '.quota-screenshot.png');
    await page.screenshot({ path: screenshotPath, fullPage: true });
    console.log(`Screenshot saved to ${screenshotPath}`);

    await browser.close();

    // Check if we got meaningful data
    const hasData = usageData.session.percent > 0 || usageData.weekly.percent > 0;

    if (hasData) {
      return {
        fetchedAt: new Date().toISOString(),
        status: 'ok',
        session: usageData.session,
        weekly: usageData.weekly,
        sonnet: usageData.sonnet,
      };
    } else {
      return {
        fetchedAt: new Date().toISOString(),
        status: 'ok',
        session: { percent: 0, resetTime: '?' },
        weekly: { percent: 0, resetTime: '?' },
        sonnet: { percent: 0, resetTime: '?' },
        error: 'Could not parse usage data. Check screenshot.',
      };
    }

  } catch (error) {
    if (browser) await browser.close();

    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error('Error fetching quota:', errorMessage);

    return {
      fetchedAt: new Date().toISOString(),
      status: 'error',
      error: errorMessage,
    };
  }
}

// Main execution
const args = process.argv.slice(2);
const forceLogin = args.includes('--login');

console.log('Claude.ai Quota Fetcher');
console.log('======================');

fetchQuota(forceLogin).then(data => {
  writeCache(data);
  console.log('\nResult:', JSON.stringify(data, null, 2));

  if (data.status === 'auth_required') {
    console.log('\nRun with --login flag to authenticate:');
    console.log('  bun run fetch-quota.ts --login');
  }

  process.exit(data.status === 'ok' ? 0 : 1);
});
