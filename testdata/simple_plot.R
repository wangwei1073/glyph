library(ggplot2)

df <- read.csv("testdata/dose_response.csv", fileEncoding = "UTF-8", check.names = FALSE)

p <- ggplot(df, aes(x = 时间点, y = 肿瘤体积, colour = 分组)) +
  stat_summary(fun = mean, geom = "line") +
  stat_summary(fun = mean, geom = "point") +
  labs(x = "时间（天）", y = "肿瘤体积", colour = "分组") +
  theme_bw()

print(p)
