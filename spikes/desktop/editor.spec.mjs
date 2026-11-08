import {test,expect} from '@playwright/test';
test.beforeEach(async({page})=>{await page.goto('/');await page.waitForFunction(()=>window.spike);});
test('inactive formatting preview does not rewrite authoritative source',async({page})=>{
 const original=await page.evaluate(()=>spike.source());
 await expect(page.locator('.preview-StrongEmphasis')).toContainText('bold');
 await page.evaluate(()=>spike.select(spike.source().indexOf('bold')));
 await expect(page.locator('.cm-content')).toContainText('**bold**');
 expect(await page.evaluate(()=>spike.source())).toBe(original);
});
test('typing punctuation survives moving preview away and back',async({page})=>{
 await page.evaluate(()=>{spike.select(spike.source().indexOf('bold'));spike.focus();});
 await page.keyboard.type('-- "literal"');
 const changed=await page.evaluate(()=>spike.source());expect(changed).toContain('**-- "literal"bold**');
 await page.evaluate(()=>spike.select(0));await page.evaluate(()=>spike.select(spike.source().indexOf('literal')));
 expect(await page.evaluate(()=>spike.source())).toBe(changed);
});
test('code and table selections reveal enclosing syntax units',async({page})=>{
 for(const needle of ['register','status']){
  const part=await page.evaluate(needle=>{spike.select(spike.source().indexOf(needle));const r=spike.active();return spike.source().slice(r.from,r.to);},needle);
  expect(part).toContain(needle);expect(part).toContain(needle==='register'?'```':'| --- |');
 }
});
test('markup and script-looking source cannot execute',async({page})=>{
 await page.evaluate(()=>spike.setSource('<img src=x onerror="window.injected=1">\n\n<script>window.injected=1</script>'));
 expect(await page.evaluate(()=>window.injected)).toBeUndefined();await expect(page.locator('.cm-content img')).toHaveCount(0);
});
test('undo restores exact source after a cross-block replacement',async({page})=>{
 const original=await page.evaluate(()=>spike.source());
 const expected=await page.evaluate(()=>{const s=spike.source(),from=s.indexOf('bold'),to=s.indexOf('register')+8;spike.select(from,to);spike.focus();return s.slice(0,from)+'REPLACED'+s.slice(to);});
 await page.keyboard.type('REPLACED');expect(await page.evaluate(()=>spike.source())).toBe(expected);
 await page.keyboard.press(process.platform==='darwin'?'Meta+z':'Control+z');
 expect(await page.evaluate(()=>spike.source())).toBe(original);
});
test('1 MB source accepts an edit without source loss',async({page})=>{
 const fixture=('plain **bold** text\n').repeat(60000).slice(0,1000000);
 await page.evaluate(s=>{spike.setSource(s);spike.select(1);spike.focus();},fixture);
 await page.keyboard.type('X');expect(await page.evaluate(()=>spike.source())).toBe(fixture.slice(0,1)+'X'+fixture.slice(1));
});
test('native browser composition commits exact text without duplicate source',async({page,browserName})=>{
 test.skip(browserName!=='chromium','CDP composition probe is Chromium-specific; not a real keyboard IME session.');
 await page.evaluate(()=>{spike.setSource('first\nsecond');spike.select(2);spike.focus();});
 const cdp=await page.context().newCDPSession(page);
 await cdp.send('Input.imeSetComposition',{text:'に',selectionStart:1,selectionEnd:1});
 await cdp.send('Input.insertText',{text:'日本語'});
 await expect.poll(()=>page.evaluate(()=>spike.source())).toBe('fi日本語rst\nsecond');
});
