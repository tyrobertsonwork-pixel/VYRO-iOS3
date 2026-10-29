const { chromium } = require('playwright');
const path = require('path');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const failures = [];
  const sizes = [
    { name: 'iPhone SE width', width: 320, height: 568 },
    { name: 'small iPhone', width: 375, height: 667 },
    { name: 'modern iPhone', width: 393, height: 852 },
    { name: 'large iPhone', width: 430, height: 932 },
    { name: 'tablet portrait', width: 768, height: 1024 },
    { name: 'desktop', width: 1024, height: 768 }
  ];

  try {
    for (const size of sizes) {
      const page = await browser.newPage({ viewport: { width: size.width, height: size.height } });
      page.on('pageerror', error => failures.push(`${size.name}: uncaught JS error: ${error.message}`));
      await page.route('https://**/*', route => route.abort());
      await page.goto('file://' + path.resolve('www/index.html'), { waitUntil: 'domcontentloaded' });
      await page.waitForTimeout(250);

      const base = await page.evaluate(() => {
        const rect = element => {
          const r = element.getBoundingClientRect();
          return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height };
        };
        const visible = element => !!element && getComputedStyle(element).display !== 'none' && element.getClientRects().length > 0;
        const nav = document.querySelector('.bottom');
        const hero = document.querySelector('.hero');
        const actions = document.querySelector('.hero .actions');
        const navRect = rect(nav);
        const heroRect = rect(hero);
        const actionsRect = rect(actions);
        return {
          viewportWidth: innerWidth,
          documentWidth: document.documentElement.scrollWidth,
          bodyWidth: document.body.scrollWidth,
          navVisible: visible(nav),
          navRect,
          heroRect,
          actionsRect,
          actionsInsideHero: actionsRect.left >= heroRect.left - 1 && actionsRect.right <= heroRect.right + 1 && actionsRect.bottom <= heroRect.bottom + 1,
          navInsideViewport: !visible(nav) || (navRect.left >= -1 && navRect.right <= innerWidth + 1 && navRect.bottom <= innerHeight + 1)
        };
      });

      if (base.documentWidth > size.width + 1 || base.bodyWidth > size.width + 1)
        failures.push(`${size.name}: horizontal overflow (document ${base.documentWidth}px, viewport ${size.width}px)`);
      if (!base.actionsInsideHero) failures.push(`${size.name}: hero actions escape hero bounds`);
      if (!base.navInsideViewport) failures.push(`${size.name}: floating navigation escapes viewport`);

      // Exercise every primary page switch using the visible navigation control.
      for (const target of ['discover', 'mylist', 'settings', 'home']) {
        const button = page.locator(`[data-page="${target}"]`).filter({ has: page.locator(':visible') }).first();
        const visibleButtons = page.locator(`[data-page="${target}"]:visible`);
        if (await visibleButtons.count()) await visibleButtons.first().click();
        const active = await page.locator('#' + target).evaluate(el => el.classList.contains('active'));
        if (!active) failures.push(`${size.name}: navigation did not activate ${target}`);
      }

      // Open long detail/player overlays and confirm their content remains scrollable.
      await page.evaluate(() => {
        document.querySelector('#detailcontent').innerHTML =
          '<div class="detailhero"><h2>Layout test title</h2></div><div class="detailbody"><img alt="" src=""><div><p>' +
          'Long synopsis text '.repeat(120) +
          '</p><div class="actions"><button class="btn">Play</button><button class="btn">Save</button></div></div></div>';
        document.querySelector('#detail').classList.add('open');
      });
      const detail = await page.evaluate(() => {
        const overlay = document.querySelector('#detail');
        overlay.scrollTop = overlay.scrollHeight;
        const d = overlay.getBoundingClientRect();
        const dialog = overlay.querySelector('.dialog').getBoundingClientRect();
        return {
          overlayWidth: d.width, overlayRight: d.right,
          dialogWidth: dialog.width, dialogRight: dialog.right,
          canScroll: overlay.scrollHeight > overlay.clientHeight,
          reachedBottom: overlay.scrollTop + overlay.clientHeight >= overlay.scrollHeight - 2
        };
      });
      if (detail.overlayRight > size.width + 1 || detail.dialogRight > size.width + 1)
        failures.push(`${size.name}: detail overlay/dialog overflows horizontally`);
      if (!detail.canScroll || !detail.reachedBottom)
        failures.push(`${size.name}: long detail overlay cannot scroll to the bottom`);

      await page.evaluate(() => {
        document.querySelector('#detail').classList.remove('open');
        document.querySelector('#player').classList.add('open');
      });
      const player = await page.evaluate(() => {
        const overlay = document.querySelector('#player');
        const shell = document.querySelector('.playershell');
        const video = document.querySelector('#video');
        const o = overlay.getBoundingClientRect(), s = shell.getBoundingClientRect(), v = video.getBoundingClientRect();
        return { overlayRight:o.right, shellRight:s.right, videoRight:v.right, viewportWidth:innerWidth, scrollable:overlay.scrollHeight >= overlay.clientHeight };
      });
      if (player.overlayRight > size.width + 1 || player.shellRight > size.width + 1 || player.videoRight > size.width + 1)
        failures.push(`${size.name}: player content overflows horizontally`);

      console.log(JSON.stringify({ viewport: size.name, ...base, detail, player }));
      await page.close();
    }
  } finally {
    await browser.close();
  }

  if (failures.length) {
    console.error('\nLAYOUT AUDIT FAILED:\n- ' + failures.join('\n- '));
    process.exitCode = 1;
  } else {
    console.log('\nLAYOUT AUDIT PASSED: no horizontal overflow, hero/nav bounds are valid, navigation switches work, and detail/player overlays fit across all six viewport sizes.');
  }
})();
