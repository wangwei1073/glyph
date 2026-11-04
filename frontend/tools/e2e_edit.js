(async () => {
  try {
    const wait = (ms) => new Promise(r => setTimeout(r, ms));
    const $ = () => document.querySelector('#app').__vue_app__.config.globalProperties.$pinia;
    const s = $()._s.get('spec'), d = $()._s.get('data');
    // 清空该源的编辑（从干净状态验证）
    d.srcKey = 'none';
    await d.select('dataset:mpg');
    s.reset();
    s.spec.data.source = { type: 'dataset', name: 'mpg' };
    s.addLayer('point');
    s.spec.layers[0].aes = { x: { map: 'displ' }, y: { map: 'hwy' } };
    await wait(900);
    for (let i = 0; i < 24; i++) { await wait(250); if (!s.rendering) break; }
    await fetch('/api/edits/clear', { method: 'POST', headers: { 'Content-Type': 'application/json' },
                                      body: JSON.stringify({ source: { type: 'dataset', name: 'mpg' } }) });

    // 打开预览弹窗
    const pvBtn = [...document.querySelectorAll('.dp-srcrow button')].find(b => b.textContent.includes('预览'));
    pvBtn.click();
    await wait(1300);

    // 开编辑模式
    const sw = document.querySelector('.pvd-foot .el-switch');
    sw.click();
    await wait(600);

    // 双击第 1 行 hwy 单元格 → 编辑框出现 → 输入 40 → Enter 提交
    const hwyTh = [...document.querySelectorAll('.pvd-dialog th')].find(x => x.dataset.col === 'hwy');
    const thIdx = [...document.querySelectorAll('.pvd-dialog thead th')].indexOf(hwyTh);
    const firstRow = document.querySelector('.pvd-dialog tbody tr');
    const cell = firstRow.children[thIdx - 0]; // 有编辑列时减 1?
    // 若第 0 列是行删除列则 +1
    const firstTdTxt = firstRow.children.length > 11 ? firstRow.children[1].textContent : firstRow.children[0].textContent;
    const targetCell = firstRow.children.length > 11 ? firstRow.children[1 + thIdx - 0] : firstRow.children[thIdx];
    const before = targetCell.textContent.trim();
    // el-dialog 有行删除列：index 需对应计入
    const cellIdx = (firstRow.children.length > 11) ? thIdx + 1 : thIdx;
    targetCell.classList && (firstRow.children[cellIdx] && firstRow.children[cellIdx].dispatchEvent(new MouseEvent('dblclick', { bubbles: true })));
    await wait(400);
    const inp = document.querySelector('.pvd-dialog tbody .el-input .el-input__inner');
    if (!inp) return JSON.stringify({ err: 'no editor input', before });
    const n = Object.keys(inp).length;
    // 走 Vue 响应式：直接设置原生值 + input 事件
    inp.value = '40';
    inp.dispatchEvent(new Event('input', { bubbles: true }));
    inp.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    await wait(1400);
    // 断言：hwy 第一行 = 40（排序未变），代码面板应含精确语句
    const s2 = $()._s.get('spec');
    await s2.renderNow();
    await wait(1200);
    const code = s2.last.code || '';
    return JSON.stringify({
      before,
      codeHasEdit: /df\$hwy\[df\$\.gg_rid == \d+\] <- 40\b/.test(code),
      codeHead: code.replace(/\n/g, ' | ').slice(0, 260)
    });
  } catch (e) {
    return 'ERR:' + e.message;
  }
})()
