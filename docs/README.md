# 垂杨柳医院等级评审指标开发项目

## 📁 项目结构

| 路径 | 说明 |
|------|------|
| `AGENTS.md` / `CLAUDE.md` | Reasonix 项目配置与规范（SQL 编写约定、项目角色等） |
| `reasonix.toml` | Reasonix 全局配置（模型、权限、LSP 等） |
| `.gitignore` | Git 排除规则（排除 `.reasonix/` 本地状态文件） |
| `.reasonix/` | Reasonix 桌面应用本地状态（不同电脑不一致，不入库） |
| `sql/` | 旧版参考 SQL（暂空，可后续补充） |
| **`docs/`** | 文档目录 |
| `docs/README.md` | **本文件** — 项目文档说明 |
| `docs/表结构参考/` | **数据库表结构参考** |
| └ `垂杨柳医院ddl.md` | hdr 库全量 DDL（282 张表的建表语句） |
| └ `查询所有表DDL.sql` | 用于导出指定库所有表 DDL 的 SQL 脚本 |
| `docs/previous-sql.docx` | **既往参考 SQL** — 用户此前完成的部分指标 SQL，供 Reasonix 学习编写习惯和表关联方式 |

## 🏥 数据库

- 数据库：**PostgreSQL**
- 目标库：**hdr**（垂杨柳医院业务库）
- 核心 Schema：`cases`、`visit`、`orders`、`emr`、`patient`、`user_defined`

详细表结构见 `docs/表结构参考/垂杨柳医院ddl.md`。

## 📐 指标开发规范

参见 `AGENTS.md` / `CLAUDE.md` 中的完整规范，要点：

- 使用 PostgreSQL 语法
- 尽量避免 CTE，优先子查询 / JOIN / 派生表
- 分子/分母用 `count(*) filter (where ...)` 或子查询区分
- 日期区间明确边界（左闭右开或闭区间需注释）
- 每个指标标明章节和指标编号

## 🚀 快速开始

```bash
# 克隆到本地
git clone https://github.com/15831290932-a11y/zhibiao--evaluation.git

# 在 Reasonix 桌面应用中添加此项目文件夹
# 连接 hdr 数据库后即可开始指标 SQL 开发
```

## 🔗 GitHub

远程仓库：https://github.com/15831290932-a11y/zhibiao--evaluation.git
