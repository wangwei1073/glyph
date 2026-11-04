(async () => {
  try {
    const wait = (ms) => new Promise(r => setTimeout(r, ms));
    const pinia = document.querySelector('#app').__vue_app__.config.globalProperties.$pinia;
    const s = pinia._s.get('spec'), d = pinia._s.get('data');
    await d.select('dataset:mpg');
    s.reset();
    s.spec.data.source = { type: 'dataset', name: 'mpg' };
    s.addLayer('point');
    s.spec.layers[0].aes = { x: { map: 'displ' }, y: { map: 'hwy' }, colour: { map: 'class' }, label: { map: 'model' } };
    s.spec.layers[0].aesParams = { size: 2, alpha: 0.8 };
    s.spec.layers[0].params = { bins: 30, se: true };
    const before = JSON.parse(JSON.stringify(s.spec.layers[0]));
    await wait(200);

    // 通过 UI：点第一张卡的“更换图层类型”按钮，等 popover 出现，选“箱线图”
    const btns = [...document.querySelectorAll('.layer-card')][0]
      .querySelectorAll('.layer-ops button');
    // 更换按钮 = 文本含“更换为其他 geom”title
    const changeBtn = [...document.querySelectorAll('.layer-card')[0].querySelectorAll('.layer-ops button')]
      .find(b => (b.getAttribute('title') || '').includes('更换') || (b.title || '').includes('更换'));
    if (!changeBtn) return 'ERR: change button not found';
    changeBtn.click();
    let chip = null;
    for (let i = 0; i < 20; i++) {
      await wait(150);
      const chips = [...document.querySelectorAll('.geom-chip')].filter(c => c.offsetParent !== null);
      chip = chips.find(c => c.textContent.includes('箱线图'));
      if (chip) break;
    }
    if (!chip) return 'ERR: boxplot chip not found';
    chip.click();
    await wait(700);

    const l = s.spec.layers[0];
    const after = JSON.parse(JSON.stringify(l));
    // 生成代码检查
    for (let i = 0; i < 30; i++) { await wait(250); if (!s.rendering) break; }
    return JSON.stringify({
      geom: l.geom,
      aesKept: Object.keys(l.aes),
      aesDropped: Object.keys(before.aes).filter(k => !(k in l.aes)),
      paramsKept: Object.keys(l.params).filter(k => k in l.params),
      paramsDropped: Object.keys(before.params).filter(k => !(k in l.params)),
      aesParamsKept: Object.keys(l.aesParams),
      code: s.last.code ? s.last.code.replace(/\\n/g, ' | ').slice(0, 200) : null
    });
  } catch (e) {
    return 'ERR:' + e;
  }
})()
