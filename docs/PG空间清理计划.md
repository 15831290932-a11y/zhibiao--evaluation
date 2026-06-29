# PostgreSQL 数据库空间清理计划

> 目标库：hdr（当前 ~900GB）
> 原则：**只清理冗余，不碰业务数据**，所有操作均可回退或验证后再执行

---

## 第一步：诊断分析（只读，对库无影响）

先在 pgAdmin / DBeaver 中连上 hdr 库，运行 `sql/pg_空间分析_只读.sql`，获取以下关键信息：

| 需要关注 | 判断标准 | 如果… |
|----------|----------|-------|
| 总空间 → 表空间 vs 索引空间 | 索引占比 > 40% | 索引膨胀严重，优先重建 |
| TOP 大表 | 有超过 50GB 的表 | 重点分析这些表的死行比例 |
| 死元组比例 | > 20% | 需要 VACUUM |
| 扫描次数为 0 的索引 | idx_scan = 0 | 可安全删除 |
| 死行数多的表 | n_dead_tup > 10 万 | 需要 aggressive VACUUM |

---

## 第二步：安全清理（按顺序执行，每步可中断）

### 阶段 1：清理死元组（VACUUM）

VACUUM **不锁表，不影响读写**，可以放心跑：

```sql
-- 库级全部表普通清理（不回收空间给OS，但标记可重用）
VACUUM (VERBOSE, ANALYZE);

-- 对死行多的表做激进清理（回收空间给OS）
VACUUM (VERBOSE, ANALYZE, TRUNCATE) cases.case_base;
VACUUM (VERBOSE, ANALYZE, TRUNCATE) your_big_table_name;
```

> ⏱ 大表 VACUUM 可能几小时，建议低峰期跑
> ⚠️ VACUUM FULL 会锁表，**非必要不用**

### 阶段 2：重建膨胀索引（REINDEX）

索引膨胀占用大量空间，重建可显著回收：

```sql
-- 对最膨胀的索引逐一重建（CONCURRENTLY = 不锁表）
REINDEX INDEX CONCURRENTLY idx_name_1;
REINDEX INDEX CONCURRENTLY idx_name_2;
-- ...

-- 或对整个 schema 重建（慎用，会锁）
-- REINDEX SCHEMA CONCURRENTLY public;
```

> ⏱ 单索引重建视大小 1-30 分钟
> ✅ CONCURRENTLY 不锁表，业务无感
> 重建完成后旧索引空间会自动释放

### 阶段 3：清理无用索引

对分析结果中 `idx_scan = 0` 的索引，逐个确认后删除：

```sql
-- 先确认确实没用
SELECT idx_scan, * FROM pg_stat_user_indexes WHERE indexrelname = 'your_unused_index';

-- 确认后删除
DROP INDEX CONCURRENTLY IF EXISTS your_unused_index;
```

> ⚠️ 删除索引前务必确认，特别是唯一约束索引

### 阶段 4：清理 TOAST 膨胀

大字段（text/json/jsonb）的表容易 TOAST 膨胀：

```sql
-- 对 TOAST 表做 VACUUM
VACUUM (VERBOSE, TRUNCATE) your_lob_table;
```

---

## 第三步：长期维护

### 调优 autovacuum 参数

在 `postgresql.conf` 中调整（或 ALTER TABLE 逐表设置）：

```ini
# 全局
autovacuum_vacuum_scale_factor = 0.01    # 默认 0.2 → 太保守
autovacuum_vacuum_threshold = 1000       # 默认 50
autovacuum_vacuum_cost_limit = 2000      # 提高清理速度

# 对超大表单独设置（推荐）
ALTER TABLE cases.case_base SET (
    autovacuum_vacuum_scale_factor = 0.005,
    autovacuum_vacuum_threshold = 500,
    autovacuum_vacuum_cost_limit = 2000
);
```

### 定期维护计划

| 频率 | 操作 | 影响 |
|------|------|------|
| 每天（自动） | autovacuum | 无感 |
| 每周 | `VACUUM ANALYZE` | 无感 |
| 每月 | 检查膨胀情况 | 只读 |
| 每季 | 重建 TOP10 膨胀索引 | CONCURRENTLY 无锁 |

---

## 预期效果

| 项目 | 估算回收空间 |
|------|:----------:|
| 死元组 + 表膨胀 | 可能 30-80 GB |
| 索引膨胀（重建后） | 可能 50-150 GB |
| 无用索引 | 看情况，几 GB ~ 几十 GB |
| 合计 | **乐观估计可回收 100-250 GB** |

---

## ⚠️ 安全注意事项

1. **先跑只读分析脚本**，拿到实际数据后再决定要动哪些表/索引
2. **永远不用 VACUUM FULL** — 锁全表，生产环境风险极高
3. **永远用 CONCURRENTLY** 重建索引
4. 重要操作前确保有备份
5. 建议在 **业务低峰期（凌晨）** 执行
6. 先在一台 **从库或测试环境** 验证效果

---

## 推荐执行顺序

```
step 1: 跑 sql/pg_空间分析_只读.sql → 拿到报告
step 2: 分析报告，确定要清理的 TOP 目标
step 3: VACUUM (VERBOSE, ANALYZE)          ← 先做这个（最安全）
step 4: REINDEX INDEX CONCURRENTLY ...      ← 逐个重建大索引
step 5: DROP INDEX CONCURRENTLY ...         ← 删无用索引
step 6: 回收后再跑一遍分析脚本 → 对比效果
```
