// 定位：为何完整脚本在 rawrender 里卡住
const APP = 'http://127.0.0.1:4321'

const head = `df <- read.csv("testdata/dose_response.csv", fileEncoding = "UTF-8", check.names = FALSE)`

const variants = {
  'V1 仅读数据 + geom_point': `${head}
p <- ggplot(df, aes(x = 时间点, y = 肿瘤体积)) + geom_point()
p`,
  'V2 加 colour 分组': `${head}
p <- ggplot(df, aes(x = 时间点, y = 肿瘤体积, colour = 分组)) + geom_point()
p`,
  'V3 stat_summary 线': `${head}
p <- ggplot(df, aes(x = 时间点, y = 肿瘤体积, colour = 分组)) +
  stat_summary(fun = mean, geom = "line")
p`,
  'V4 完整 + print(p)': `${head}
p <- ggplot(df, aes(x = 时间点, y = 肿瘤体积, colour = 分组)) +
  stat_summary(fun = mean, geom = "line") +
  stat_summary(fun = mean, geom = "point") +
  labs(x = "时间（天）", y = "肿瘤体积", colour = "分组") + theme_bw()
print(p)`,
  'V5 完整 不带 print': `${head}
p <- ggplot(df, aes(x = 时间点, y = 肿瘤体积, colour = 分组)) +
  stat_summary(fun = mean, geom = "line") +
  stat_summary(fun = mean, geom = "point") +
  labs(x = "时间（天）", y = "肿瘤体积", colour = "分组") + theme_bw()
p`
}

for (const [label, code] of Object.entries(variants)) {
  const t0 = Date.now()
  const ac = new AbortController()
  const timer = setTimeout(() => ac.abort(), 25000)
  try {
    const r = await fetch(`${APP}/api/rawrender`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: JSON.stringify({
        code,
        spec: { data: { source: { type: 'none' } }, layers: [], theme: { base: 'minimal' } },
        width: 800, height: 600, dpi: 150
      }),
      signal: ac.signal
    })
    const j = await r.json()
    console.log(`${label} -> ok=${j.ok} ${j.elapsedMs ?? '?'}ms ${j.error ? String(j.error).slice(0, 70) : ''} (墙钟 ${Date.now() - t0}ms)`)
  } catch (e) {
    console.log(`${label} -> 超时/失败: ${e.name} (墙钟 ${Date.now() - t0}ms)`)
  } finally {
    clearTimeout(timer)
  }
}
