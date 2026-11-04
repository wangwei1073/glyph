(async () => {
  try {
    const wait = (ms) => new Promise(r => setTimeout(r, ms));
    const $ = () => document.querySelector('#app').__vue_app__.config.globalProperties.$pinia;
    const s = $()._s.get('spec');
    const out = {};
    // 当前状态：弹窗刚完成改名 + 两次 undo（清空）？保险：重新走一遍
    // 1) 类型校验拒绝测试
    const hwyTh = [...document.querySelectorAll('.pvd-dialog th')].find(x => x.dataset.col === 'hwy' || x.dataset.col === 'hwy_v');
    if (!hwyTh) return 'ERR: dialog closed';
    const thAll = [...document.querySelectorAll('.pvd-dialog thead th')];
    const hwyIdx = thAll.indexOf(hwyTh);
    const colName = hwyTh.dataset.col;
    const row0 = document.querySelector('.pvd-dialog tbody tr');
    const cellIdx = row0.children.length > 11 ? hwyIdx + 1 : hwyIdx;
    row0.children[cellIdx].dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
    await wait(400);
    const inp = document.querySelector('.pvd-dialog tbody .el-input__inner');
    if (!inp) return 'ERR: editor input missing';
    inp.value = 'abc';
    inp.dispatchEvent(new Event('input', { bubbles: true }));
    inp.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    await wait(800);
    const alert = document.querySelector('.pvd-dialog .el-alert--error');
    out.rejected = alert ? alert.textContent.replace(/\s+/g, ' ').slice(0, 80) : 'NO-ALERT';
    const inp2 = document.querySelector('.pvd-dialog tbody .el-input__inner');
    if (inp2) inp2.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    await wait(300);
    return JSON.stringify(out);
  } catch (e) {
    return 'ERR:' + e.message;
  }
})()
