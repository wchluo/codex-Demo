# codex-Demo
CodeX coding practice

## 使用说明

`process_iso.pl` 用于扫描蓝光 ISO 中的长片段并分装为 MKV。

1. **生成任务列表**
   ```bash
   perl process_iso.pl --prepare *.iso --season S01
   ```
   执行后会在当前目录生成 `tasks.csv`，请人工确认其中的标题信息。

2. **按任务执行提取与分装**
   ```bash
   perl process_iso.pl --run --tasks tasks.csv
   ```
   脚本会挂载 ISO、提取对应的 m2ts，并用 ffmpeg 无损封装为 MKV。
