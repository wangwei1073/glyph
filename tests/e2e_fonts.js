(async () => {
  try {
    const wait = (ms) => new Promise(r => setTimeout(r, ms));
    const pinia = document.querySelector('#app').__vue_app__.config.globalProperties.$pinia;
    const s = pinia._s.get('spec'), d = pinia._s.get('data');
    await d.select('dataset:mpg');
    s.reset();
    s.spec.data.source = { type: 'dataset', name: 'mpg' };
    s.addLayer('point');
    s.spec.layers[0].aes = { x: { map: 'displ' }, y: { map: 'hwy' }, colour: { map: 'class' } };
    s.spec.labs = { title: '标题测试 Fonts', subtitle: '副标题也可以排版', caption: '来源: ggplotGUI' };
    // 模拟"标签面板的字体弹层"写入：字号/粗体/颜色/角度/边距
    s.spec.theme.elements['plot.title'] = { type: 'text', props: { size: 17, face: 'bold', colour: '#8e44ad', margin: { b: 10 } } };
    s.spec.theme.elements['plot.subtitle'] = { type: 'text', props: { size: 12, colour: '#7f8c8d', face: 'italic' } };
    s.spec.theme.elements['plot.caption'] = { type: 'text', props: { size: 10, colour: '#999999', angle: 0 } };
    await wait(1600);
    for (let i = 0; i < 30; i++) { await wait(300); if (!s.rendering) break; }
    return JSON.stringify({
      ok: s.last.ok, err: s.last.error,
      code: s.last.code ? s.last.code.replace(/\\n/g, ' | ').slice(-330) : null
    });
  } catch (e) {
    return 'ERR:' + e;
  }
})()
