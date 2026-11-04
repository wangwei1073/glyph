(async () => {
  try {
    const wait = (ms) => new Promise(r => setTimeout(r, ms));
    const $ = () => document.querySelector('#app').__vue_app__.config.globalProperties.$pinia;
    const s = $()._s.get('spec');
    const out = {};
    // 弹窗应仍开着（上一步）——重建状态保险
    if (!document.querySelectorAll('.pvd-dialog').length) {
      const pvBtn = [...document.querySelectorAll('.dp-srcrow button')].find(b => b.textContent.includes('预览'));
      pvBtn.click();
      await wait(1200);
      document.querySelector('.pvd-foot .el-switch').click();
      await wait(500);
    }
    // 1) 类型校验：双击第一行 hwy → 输入 abc → Enter → 应被拒并显示错误
    const hwyTh = [...document.querySelectorAll('.pvd-dialog th')].find(x => x.dataset.col === 'hwy');
    const thAll = [...document.querySelectorAll('.pvd-dialog thead th')];
    const hwyIdx = thAll.indexOf(hwyTh);
    const row0 = document.querySelector('.pvd-dialog tbody tr');
    const cellIdx = row0.children.length > 11 ? hwyIdx + 1 : hwyIdx;
    row0.children[cellIdx].dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
    await wait(350);
    const inp = document.querySelector('.pvd-dialog tbody .el-input .el-input__inner');
    inp.value = 'abc';
    inp.dispatchEvent(new Event('input', { bubbles: true }));
    inp.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    await wait(700);
    out.rejected = (document.querySelector('.pvd-dialog .el-alert--error') || {}).textContent;
    out.rejected = out.rejected ? (out.rejected || '').replace(/\s+/g, ' ').slice(0, 60) : null;
    const esc = document.querySelector('.pvd-dialog tbody .el-input .el-input__inner');
    if (esc) esc.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    await wait(250);

    // 2) 列改名：hwy → hwy_v（列菜单里的改名按钮）
    const menu = hwyTh.querySelector('.pvd-menu');
    menu.click();
    await wait(400);
    const renBtn = [...document.querySelectorAll('.pvd-menu-body .el-button')].filter(b => b.offsetParent !== null)
      .find(b => b.textContent.trim() === '改名');
    if (!renBtn) return JSON.stringify({ err: 'no rename btn' });
    renBtn.click();
    await wait(500);
    const msgInp = document.querySelector('.el-message-box .el-input input');
    msgInp.value = 'hwy_v';
    msgInp.dispatchEvent(new Event('input', { bubbles: true }));
    const okBtn = [...document.querySelectorAll('.el-message-box button')].find(b => b.textContent.includes('确定'));
    okBtn.click();
    await wait(1400);
    await s.renderNow(); await wait(900);
    const code1 = s.last.code || '';
    out.renamed = /names\(df\)\[names\(df\) == "hwy"\] <- "hwy_v"/.test(code1) &&
                  /y = hwy_v/.test(code1);
    // 3) 撤销 cell 编辑（第一次 cell→40 在此前被推入）→ undo 后代码应无 <- 40 手动行
    const undoBtn = document.querySelector('.pvd-foot .el-tooltip__trigger') ||
                    document.querySelector('.pvd-foot .el-icon--left')?.closest('button');
    (undoBtn || { click() {} }).click();
    await wait(1000);
    await s.renderNow(); await wait(900);
    const code2 = s.last.code || '';
    out.undoDroppedCell = !/<- 40\b/.test(code2);
    // 4) 撤销 rename
    (undoBtn || { click() {} }).click();
    await wait(1000);
    await s.renderNow(); await wait(900);
    const code3 = s.last.code || '';
    out.undoRenamed = !/hwy_v/.test(code3) && /y = hwy\b/.test(code3);
    out.count = (await (await fetch('/api/edits?key=' + encodeURIComponent('dataset:mpg'))).json()).count;
    return JSON.stringify(out);
  } catch (e) {
    return 'ERR:' + e.message;
  }
})()
