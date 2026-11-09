<script setup>
// 远程数据库工作区（v2）：连接 / 表树 / 预览，使用全局会话 store
import { onMounted } from 'vue'
import { useRemoteDbStore } from '../stores/remoteDb'

const db = useRemoteDbStore()
const TYPE_CLASS = { num: 'num', chr: 'chr', fct: 'fct', lgl: 'lgl', date: 'date', dttm: 'date' }

onMounted(() => db.loadDrivers())
</script>

<template>
  <div class="db-cols">
    <!-- 左：连接 -->
    <div class="col left">
      <div class="col-h">连接</div>
      <div class="drv">
        <button v-for="d in db.drivers" :key="d.id" class="d" :class="{ on: db.driver === d.id }"
          @click="db.setDriver(d.id)">
          <span class="st" :class="{ ok: d.installed }" />{{ d.label }}
        </button>
      </div>

      <el-alert v-if="!db.installed" type="warning" :closable="false">
        <template #title>
          {{ db.driverDef?.label }} 驱动（{{ db.driverDef?.pkg }}）未安装
          <el-button size="small" text type="primary" :loading="!!db.installing" @click="db.installDriver">
            立即安装
          </el-button>
        </template>
      </el-alert>

      <template v-if="!db.connId">
        <div class="form">
          <div class="r2">
            <div><span class="lbl">主机</span><el-input v-model="db.form.host" size="small" /></div>
            <div><span class="lbl">端口</span><el-input v-model.number="db.form.port" size="small" /></div>
          </div>
          <div class="r2">
            <div><span class="lbl">数据库</span><el-input v-model="db.form.dbname" size="small" /></div>
            <div><span class="lbl">用户</span><el-input v-model="db.form.user" size="small" /></div>
          </div>
          <div class="r2">
            <div><span class="lbl">密码</span><el-input v-model="db.form.password" type="password" size="small" show-password /></div>
            <div v-if="db.driver === 'postgres'"><span class="lbl">SSL</span>
              <el-select v-model="db.form.sslmode" size="small" style="width:100%">
                <el-option value="prefer" label="prefer" />
                <el-option value="require" label="require" />
                <el-option value="disable" label="disable" />
              </el-select>
            </div>
            <div v-else-if="db.driver === 'odbc'"><span class="lbl">DSN</span><el-input v-model="db.form.dsn" size="small" /></div>
            <div v-else />
          </div>
        </div>
        <div class="btns">
          <el-button size="small" :loading="db.testing" :disabled="!db.installed" @click="db.test">测试连接</el-button>
          <el-button size="small" type="primary" :loading="db.connecting" :disabled="!db.installed" @click="db.connect">
            连接
          </el-button>
        </div>
        <div class="hint">密码只保存在本次会话内存，不写入项目或日志。</div>
      </template>

      <template v-else>
        <div class="conn-badge"><span class="dot" />已连接 · {{ db.connInfo?.dbname }}<span class="ok">只读</span></div>
        <div class="conn-card">
          <div class="kv">主机<b>{{ db.form.host }}:{{ db.form.port }}</b></div>
          <div class="kv">用户<b>{{ db.form.user || '—' }}</b></div>
          <div class="kv">SSL<b>{{ db.form.sslmode }}</b></div>
          <div class="kv">会话<b>只读</b></div>
          <div class="btns">
            <el-button size="small" @click="db.disconnect">断开</el-button>
            <el-button size="small" @click="db.loadTables">刷新表</el-button>
          </div>
        </div>
        <div class="hint">导入会创建结果快照；断开数据库不影响已导入数据与已有图形。</div>
      </template>

      <el-alert v-if="db.testMsg" type="success" :title="db.testMsg" :closable="false" />
      <el-alert v-if="db.error" type="error" :title="db.error" :closable="false" />
    </div>

    <!-- 中：表树 -->
    <div class="col mid">
      <div class="col-h">表 <span class="hint">{{ db.tables.length }} 张</span></div>
      <el-input v-model="db.search" size="small" placeholder="搜索表…" clearable>
        <template #prefix><el-icon><Search /></el-icon></template>
      </el-input>
      <div v-if="db.connId" class="tree">
        <template v-for="s in db.filteredSchemas" :key="s.name || 'default'">
          <div class="node grp"><span class="caret">▾</span>{{ s.name || 'default' }}<span class="n">{{ s.tables.length }}</span></div>
          <button v-for="t in s.tables" :key="(t.schema || '') + t.name" class="node child"
            :class="{ sel: !db.sqlMode && db.tableSel && db.tableSel.name === t.name && db.tableSel.schema === t.schema }"
            @click="db.selectTable(t)">
            {{ t.name }}<span class="n">{{ t.rows ?? '' }}</span>
          </button>
        </template>
        <div v-if="!db.filteredSchemas.length" class="empty sm">没有匹配的表</div>
      </div>
      <div v-else class="empty sm">连接后加载 schema 与表</div>
      <el-button v-if="db.connId" size="small" text type="primary" style="justify-content:flex-start"
        @click="db.enterSql">自定义 SQL…</el-button>
    </div>

    <!-- 右：预览 -->
    <div class="col right">
      <div class="col-h">预览
        <span v-if="db.preview" class="hint">{{ db.preview.columns.length }} 列 · {{ db.preview.previewRows }} 行</span>
        <span class="sp" />
        <span v-if="db.connId" class="hint">只读</span>
      </div>
      <div v-if="db.sqlMode" class="sql-edit">
        <el-input v-model="db.sql" type="textarea" :rows="3" class="gg-mono"
          placeholder="SELECT * FROM ...（只允许单条 SELECT / WITH）" />
        <el-button size="small" type="primary" :loading="db.loading" @click="db.runSql">运行</el-button>
      </div>
      <div v-else-if="db.preview?.sql" class="sqlbar gg-mono" @click="db.enterSql">{{ db.preview.sql }}</div>

      <el-table v-if="db.preview" :data="db.preview.rows" size="small" height="330" border v-loading="db.loading">
        <el-table-column v-for="c in db.preview.columns" :key="c.name" :prop="c.name" min-width="110">
          <template #header>
            <span class="cn">{{ c.name }}</span>
            <span class="tp" :class="TYPE_CLASS[c.type] || 'chr'">{{ c.type }}</span>
          </template>
        </el-table-column>
      </el-table>
      <div v-else class="empty">
        {{ db.connId ? '选择左侧表，或点「自定义 SQL…」运行只读查询' : '连接成功后显示表与预览' }}
      </div>
    </div>
  </div>
</template>

<style scoped>
.db-cols { display: flex; min-height: 470px; }
.col { display: flex; flex-direction: column; gap: 8px; }
.col.left { width: 300px; border-right: 1px solid var(--gg-border); padding-right: 12px; }
.col.mid { width: 216px; border-right: 1px solid var(--gg-border); padding: 0 12px; min-width: 0; }
.col.right { flex: 1; padding-left: 12px; min-width: 0; }
.col-h { display: flex; align-items: center; gap: 6px; font-size: 11.5px; color: var(--gg-text-3); font-weight: 600; }
.col-h .sp { flex: 1; }
.lbl { display: block; font-size: 11px; color: var(--gg-text-3); margin-bottom: 4px; }
.hint { font-size: 11.5px; color: var(--gg-text-4); }
.form { display: flex; flex-direction: column; gap: 8px; }
.r2 { display: flex; gap: 8px; }
.r2 > div { flex: 1; min-width: 0; }
.btns { display: flex; gap: 8px; }
.btns .el-button { flex: 1; margin: 0; }
.drv { display: flex; gap: 6px; }
.drv .d {
  flex: 1; min-width: 0; border: 1px solid var(--gg-border); background: #fff; border-radius: 4px;
  padding: 4px 6px; font-size: 11.5px; color: var(--gg-text-2); cursor: pointer;
  display: flex; align-items: center; justify-content: center; gap: 5px;
}
.drv .d.on { border-color: var(--gg-brand); color: var(--gg-brand); background: var(--gg-brand-2, #eaf1fb); }
.drv .st { width: 6px; height: 6px; border-radius: 50%; background: #d0d6de; flex-shrink: 0; }
.drv .st.ok { background: #2e9e6b; }
.conn-badge {
  display: flex; align-items: center; gap: 6px; font-size: 12px; color: var(--gg-text-2);
  background: #f4faf7; border: 1px solid #d9efe4; border-radius: 6px; padding: 7px 9px;
}
.conn-badge .dot { width: 6px; height: 6px; border-radius: 50%; background: #2e9e6b; }
.conn-badge .ok { margin-left: auto; font-size: 10.5px; color: #2e9e6b; font-weight: 600; }
.conn-card { border: 1px solid var(--gg-border); border-radius: 8px; background: #fcfdff; padding: 10px; }
.kv { display: flex; font-size: 11.5px; color: var(--gg-text-3); line-height: 1.9; }
.kv b { color: var(--gg-text-2); font-weight: 600; margin-left: auto; }
.tree { display: flex; flex-direction: column; gap: 1px; max-height: 300px; overflow: auto; }
.node { display: flex; align-items: center; gap: 5px; padding: 3px 5px; border-radius: 4px; font-size: 12px; color: var(--gg-text-2); }
.node.grp { color: var(--gg-text-3); font-size: 11px; font-weight: 600; margin-top: 2px; }
.node.child { padding-left: 18px; border: 0; background: transparent; text-align: left; cursor: pointer; }
.node.child:hover { background: rgba(47,111,191,.07); }
.node.child.sel { background: var(--gg-brand-2, #eaf1fb); color: var(--gg-brand); font-weight: 600; }
.node .caret { width: 10px; font-size: 10px; color: var(--gg-text-4); }
.node .n { margin-left: auto; font-size: 10.5px; color: var(--gg-text-4); }
.empty { color: var(--gg-text-4); font-size: 12px; padding: 30px; text-align: center; border: 1px dashed var(--gg-border); border-radius: 6px; }
.empty.sm { padding: 16px 8px; font-size: 11.5px; }
.sqlbar {
  border: 1px solid var(--gg-border); border-radius: 6px; background: #fbfcfe;
  padding: 6px 8px; font-size: 11px; color: var(--gg-text-2); cursor: text;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.sql-edit { display: flex; gap: 8px; align-items: flex-start; }
.sql-edit .el-button { flex-shrink: 0; }
.cn { margin-right: 4px; }
.tp { font-size: 10px; border-radius: 3px; padding: 0 3px; line-height: 14px; }
.tp.num { background: #e8f1fa; color: #2170b5; }
.tp.chr { background: #fdf3e3; color: #c07f18; }
.tp.fct { background: #eaf5e6; color: #3e8929; }
.tp.lgl { background: #f3eaf8; color: #8d3fb0; }
.tp.date { background: #fdeee3; color: #c55a11; }
</style>
