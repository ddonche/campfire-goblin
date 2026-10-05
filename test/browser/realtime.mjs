// Two people in one room: what one posts shows up for the other through the
// cable shim, and the composer, presence and typing paths run without errors.
//   node test/browser/realtime.mjs [base-url] [room-id]
import { createRequire } from "node:module"
const { chromium } = createRequire(import.meta.url)("playwright")

const base = process.argv[2] || "http://127.0.0.1:3002"
const room = process.argv[3] || "486777696"
const password = "secret123456"

async function signIn(browser, email) {
  const context = await browser.newContext()
  const page = await context.newPage()
  page.errors = []
  page.on("pageerror", error => page.errors.push(error.message))
  page.on("console", message => { if (message.type() === "error") page.errors.push(message.text()) })
  await page.goto(`${base}/session/new`)
  await page.fill("input[name=email_address]", email)
  await page.fill("input[name=password]", password)
  await Promise.all([ page.waitForURL(/\/rooms\//), page.click("button[type=submit]") ])
  await page.goto(`${base}/rooms/${room}`)
  return page
}

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined })
try {
  const david = await signIn(browser, "david@37signals.com")
  const jason = await signIn(browser, "jason@37signals.com")

  // Wait for both to be subscribed to the room's messages.
  for (const page of [ david, jason ]) {
    await page.waitForFunction(() => document.querySelector("turbo-cable-stream-source[connected]"), null, { timeout: 15000 })
  }

  const text = `Hello from Jason ${Date.now()}`
  await jason.click("lexxy-editor")
  await jason.keyboard.type(text)
  await jason.keyboard.press("Enter")

  await david.waitForSelector(`.message:has-text("${text}")`, { timeout: 30000 })
  console.log("david received:", text)
  await jason.waitForSelector(`.message:has-text("${text}")`, { timeout: 10000 })
  const copies = await jason.locator(`.message:has-text("${text}")`).count()
  console.log("jason sees it", copies, "time(s)")

  for (const [ name, page ] of [ [ "david", david ], [ "jason", jason ] ]) {
    if (page.errors.length) console.log(`${name} errors:`, page.errors)
  }
  if (copies !== 1) process.exitCode = 1
} finally {
  await browser.close()
}
