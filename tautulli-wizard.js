// Tautulli Setup Wizard - Puppeteer Automation
// Completes the first-run wizard on remote VM with Plex OAuth handling

const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');

puppeteer.use(StealthPlugin());

// VM access - Tautulli is on the remote VM
const TAUTULLI_URL = 'http://10.0.1.204:8181';

// Plex credentials
const PLEX_USERNAME = 'simonbarker@gmail.com';
const PLEX_PASSWORD = 'St@rbuck000';
const PLEX_TOKEN = '4BCJYy3xqcG6kQHSLfPF';
const PLEX_SERVER_IP = '10.0.2.111';

async function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function findButtonByText(page, textPattern) {
    const buttons = await page.$$('button, a.btn, input[type="submit"]');
    for (const btn of buttons) {
        const text = await page.evaluate(el => (el.innerText || el.textContent || el.value || '').trim(), btn);
        const isVisible = await page.evaluate(el => {
            const rect = el.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0 && el.offsetParent !== null;
        }, btn);
        if (isVisible && textPattern.test(text)) {
            return btn;
        }
    }
    return null;
}

async function completeTautulliWizard() {
    console.log('Starting Tautulli Setup Wizard automation...');
    console.log(`Target URL: ${TAUTULLI_URL}`);

    const browser = await puppeteer.launch({
        headless: false,
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-blink-features=AutomationControlled',
            '--window-size=1400,900'
        ]
    });

    const page = await browser.newPage();
    await page.setViewport({ width: 1400, height: 900 });

    try {
        console.log('Navigating to Tautulli...');
        await page.goto(TAUTULLI_URL, { waitUntil: 'networkidle2', timeout: 30000 });
        await sleep(2000);

        const title = await page.title();
        console.log('Page title:', title);

        const pageContent = await page.content();

        if (pageContent.includes('Setup Wizard') || pageContent.includes('Welcome')) {
            console.log('Setup wizard detected. Starting wizard completion...\n');

            // Step 1: Welcome - Click Next
            console.log('=== Step 1: Welcome ===');
            await page.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-step1-welcome.png' });
            let nextBtn = await findButtonByText(page, /^Next$/i);
            if (nextBtn) {
                console.log('Clicking Next...');
                await nextBtn.click();
                await sleep(2000);
            }

            // Step 2: Authentication - Set username/password
            console.log('\n=== Step 2: Authentication ===');
            await page.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-step2-auth.png' });

            const usernameInput = await page.$('input[name="http_username"], input#http_username');
            const passwordInput = await page.$('input[name="http_password"], input#http_password');

            if (usernameInput) {
                console.log('Entering username: admin');
                await usernameInput.click({ clickCount: 3 });
                await usernameInput.type('admin');
            }
            if (passwordInput) {
                console.log('Entering password');
                await passwordInput.click({ clickCount: 3 });
                await passwordInput.type('St@rbuck000');
            }

            nextBtn = await findButtonByText(page, /^Next$/i);
            if (nextBtn) {
                console.log('Clicking Next...');
                await nextBtn.click();
                await sleep(2000);
            }

            // Step 3: Plex Account - Handle OAuth popup
            console.log('\n=== Step 3: Plex Account ===');
            await page.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-step3-plex-account.png' });

            // Look for Sign in with Plex button
            const plexSignInBtn = await page.$('#sign-in-plex, button[id*="plex"], a[id*="plex"]');

            if (plexSignInBtn) {
                console.log('Found "Sign in with Plex" button');

                // Set up popup handler before clicking
                const popupPromise = new Promise(resolve => {
                    browser.once('targetcreated', async target => {
                        const popup = await target.page();
                        resolve(popup);
                    });
                });

                // Click the Sign in with Plex button
                console.log('Clicking Sign in with Plex...');
                await plexSignInBtn.click();

                // Wait for popup
                console.log('Waiting for Plex OAuth popup...');
                const popup = await popupPromise;

                if (popup) {
                    console.log('Popup opened, waiting for it to load...');
                    await popup.setViewport({ width: 600, height: 800 });
                    await sleep(3000);

                    // Take screenshot of popup
                    await popup.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-plex-popup.png' });

                    const popupUrl = popup.url();
                    console.log('Popup URL:', popupUrl);

                    // Handle Plex login
                    if (popupUrl.includes('plex.tv')) {
                        console.log('Plex login page detected');

                        // Wait for email input
                        await popup.waitForSelector('input[type="email"], input[name="email"], #email', { timeout: 10000 });

                        // Enter email
                        const emailInput = await popup.$('input[type="email"], input[name="email"], #email');
                        if (emailInput) {
                            console.log('Entering Plex email...');
                            await emailInput.type(PLEX_USERNAME);
                            await sleep(500);
                        }

                        // Enter password
                        const passInput = await popup.$('input[type="password"], input[name="password"], #password');
                        if (passInput) {
                            console.log('Entering Plex password...');
                            await passInput.type(PLEX_PASSWORD);
                            await sleep(500);
                        }

                        // Click Sign In button
                        await popup.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-plex-login-filled.png' });

                        const signInBtn = await popup.$('button[type="submit"], input[type="submit"], button:has-text("Sign In")');
                        if (signInBtn) {
                            console.log('Clicking Sign In...');
                            await signInBtn.click();
                        } else {
                            // Try finding by text
                            const buttons = await popup.$$('button');
                            for (const btn of buttons) {
                                const text = await popup.evaluate(el => el.innerText, btn);
                                if (text && text.toLowerCase().includes('sign in')) {
                                    console.log('Found Sign In button by text, clicking...');
                                    await btn.click();
                                    break;
                                }
                            }
                        }

                        await sleep(5000);
                        await popup.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-plex-after-login.png' });

                        // May need to allow access
                        const allowBtn = await popup.$('button:has-text("Allow"), button.allow');
                        if (allowBtn) {
                            console.log('Clicking Allow...');
                            await allowBtn.click();
                            await sleep(3000);
                        }
                    }

                    // Wait for popup to close or redirect
                    await sleep(5000);
                }
            } else {
                console.log('No Plex sign-in button found, trying Next...');
            }

            // Back to main page - try clicking Next
            await sleep(2000);
            await page.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-after-plex-auth.png' });

            nextBtn = await findButtonByText(page, /^Next$/i);
            if (nextBtn) {
                const isDisabled = await page.evaluate(el => el.disabled || el.classList.contains('disabled'), nextBtn);
                if (!isDisabled) {
                    console.log('Clicking Next after Plex auth...');
                    await nextBtn.click();
                    await sleep(2000);
                }
            }

            // Step 4: Plex Media Server
            console.log('\n=== Step 4: Plex Media Server ===');
            await page.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-step4-pms.png' });

            // Check if there's a server selection or manual entry
            const currentContent = await page.evaluate(() => document.body.innerText);
            console.log('Current step content preview:', currentContent.substring(0, 200));

            // Look for server selection dropdown or manual input fields
            const serverSelect = await page.$('select#pms_identifier, select[name="pms_identifier"]');
            if (serverSelect) {
                console.log('Found server selection dropdown');
                // Get options
                const options = await page.$$eval('select#pms_identifier option, select[name="pms_identifier"] option', opts =>
                    opts.map(o => ({ value: o.value, text: o.innerText }))
                );
                console.log('Available servers:', options);
                // Select first non-empty option
                if (options.length > 1) {
                    await page.select('select#pms_identifier, select[name="pms_identifier"]', options[1].value);
                }
            }

            nextBtn = await findButtonByText(page, /^Next$/i);
            if (nextBtn) {
                console.log('Clicking Next...');
                await nextBtn.click();
                await sleep(2000);
            }

            // Step 5: Activity Logging
            console.log('\n=== Step 5: Activity Logging ===');
            await page.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-step5-logging.png' });
            nextBtn = await findButtonByText(page, /^Next$/i);
            if (nextBtn) {
                console.log('Clicking Next...');
                await nextBtn.click();
                await sleep(2000);
            }

            // Step 6: Notifications
            console.log('\n=== Step 6: Notifications ===');
            await page.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-step6-notifications.png' });
            nextBtn = await findButtonByText(page, /^Next$/i);
            if (nextBtn) {
                console.log('Clicking Next...');
                await nextBtn.click();
                await sleep(2000);
            }

            // Step 7: Database Import
            console.log('\n=== Step 7: Database Import ===');
            await page.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-step7-import.png' });

            // Look for Finish button
            let finishBtn = await findButtonByText(page, /Finish|Complete|Done/i);
            if (finishBtn) {
                console.log('Clicking Finish...');
                await finishBtn.click();
                await sleep(3000);
            } else {
                nextBtn = await findButtonByText(page, /^Next$/i);
                if (nextBtn) {
                    console.log('Clicking Next...');
                    await nextBtn.click();
                    await sleep(2000);
                }
            }

            // Final screenshot
            await page.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-final.png', fullPage: true });

        } else {
            console.log('No setup wizard detected - Tautulli may already be configured');
            await page.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-configured.png' });
        }

        const finalUrl = page.url();
        const finalTitle = await page.title();
        console.log(`\n=== Final State ===`);
        console.log(`URL: ${finalUrl}`);
        console.log(`Title: ${finalTitle}`);

    } catch (error) {
        console.error('Error during wizard:', error.message);
        console.error(error.stack);
        await page.screenshot({ path: 'C:/git/DockArr-Stack/tautulli-error.png' });
    } finally {
        console.log('\nKeeping browser open for 10 seconds...');
        await sleep(10000);
        await browser.close();
    }
}

completeTautulliWizard()
    .then(() => {
        console.log('\nWizard automation complete');
        process.exit(0);
    })
    .catch(err => {
        console.error('Fatal error:', err);
        process.exit(1);
    });
