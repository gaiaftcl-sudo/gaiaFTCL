# STATUS: CRITICAL Removed from GaiaFusion UI

**Date**: 2026-04-15  
**Issue**: User reported "STATUS: CRITICAL" appearing in the live GaiaFusion app UI  
**Root Cause**: Next.js fusion-s4 dashboard used `'CRITICAL'` as a `CellState` enum value and displayed it in 11 languages

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Originating Geometry (Triangulated)

### 1. Type Definition (`services/gaiaos_ui_web/app/fusion-s4/page.tsx` line 17)

```typescript
type CellState = 'MOORED' | 'ACTIVE' | 'CRITICAL';  // BEFORE
type CellState = 'MOORED' | 'ACTIVE' | 'OFFLINE';   // AFTER
```

### 2. Status Assignment Logic (line 254-261)

```typescript
const offline = statusLower === 'offline' || (active === false && Number.isFinite(hNum) && hNum <= 0);
let uiStatus: CellState = 'MOORED';
if (offline) {
  uiStatus = 'CRITICAL';  // BEFORE
  uiStatus = 'OFFLINE';   // AFTER
}
```

### 3. Projection Status Mapping (line 321-326)

```typescript
status:
  toText(meshData.status) === 'CRITICAL'  // BEFORE
    ? 'CRITICAL'
  toText(meshData.status) === 'OFFLINE'   // AFTER
    ? 'OFFLINE'
```

### 4. Ribbon Status Display (line 656-669)

```typescript
const ribbonStatusLine = (shell: FusionGlobalI18n, projection: ProjectionSnapshot | null): string => {
  if (!projection || !projection.natsOk) {
    return shell.ribbon_status_critical;  // BEFORE
    return shell.ribbon_status_offline;   // AFTER
  }
  switch (projection.status) {
    case 'CRITICAL':  // BEFORE
    case 'OFFLINE':   // AFTER
      return shell.ribbon_status_critical;  // BEFORE
      return shell.ribbon_status_offline;   // AFTER
```

### 5. Cell Grid Offline Check (line 1237)

```typescript
const offline = cell.status === 'CRITICAL';  // BEFORE
const offline = cell.status === 'OFFLINE';   // AFTER
```

### 6. I18n Type Definition (`services/gaiaos_ui_web/app/fusion-s4/fusionGlobalI18n.ts` line 28-38)

```typescript
export type FusionShellRibbonNav = {
  ribbon_status_moored: string;
  ribbon_status_unmoored: string;
  ribbon_status_critical: string;  // BEFORE → ribbon_status_offline: string;  // AFTER
  ribbon_status_active: string;    // ADDED
  ribbon_cell_count: string;
  ribbon_variant: string;
  nav_grid: string;
  nav_topology: string;
  nav_projection: string;
  nav_metrics: string;
};
```

### 7. I18n String Values (11 locales, lines 250-381)

**English (en-US, en-GB)**:
- `ribbon_status_offline: 'STATUS: CRITICAL'` → `'STATUS: OFFLINE'`
- `ribbon_status_active: 'STATUS: ACTIVE'` (ADDED)

**Chinese (zh-CN)**:
- `ribbon_status_offline: '状态：严重'` → `'状态：离线'` (critical → offline)
- `ribbon_status_active: '状态：活跃'` (ADDED)

**Japanese (ja-JP)**:
- `ribbon_status_offline: 'ステータス：重大'` → `'ステータス：オフライン'`
- `ribbon_status_active: 'ステータス：稼働中'` (ADDED)

**Korean (ko-KR)**:
- `ribbon_status_offline: '상태: 심각'` → `'상태: 오프라인'`
- `ribbon_status_active: '상태: 활성'` (ADDED)

**Russian (ru-RU)**:
- `ribbon_status_offline: 'СТАТУС: КРИТИЧЕСКИЙ'` → `'СТАТУС: ОТКЛЮЧЁН'`
- `ribbon_status_active: 'СТАТУС: АКТИВЕН'` (ADDED)

**German (de-DE)**:
- `ribbon_status_offline: 'STATUS: KRITISCH'` → `'STATUS: OFFLINE'`
- `ribbon_status_active: 'STATUS: AKTIV'` (ADDED)

**French (fr-FR)**:
- `ribbon_status_offline: 'STATUT : CRITIQUE'` → `'STATUT : HORS LIGNE'`
- `ribbon_status_active: 'STATUT : ACTIF'` (ADDED)

**Italian (it-IT)**:
- `ribbon_status_offline: 'STATO: CRITICO'` → `'STATO: NON IN LINEA'`
- `ribbon_status_active: 'STATO: ATTIVO'` (ADDED)

**Spanish (es-ES)**:
- `ribbon_status_offline: 'ESTADO: CRÍTICO'` → `'ESTADO: FUERA DE LÍNEA'`
- `ribbon_status_active: 'ESTADO: ACTIVO'` (ADDED)

**Hindi (hi-IN)**:
- `ribbon_status_offline: 'स्थिति: गंभीर'` → `'स्थिति: ऑफ़लाइन'`
- `ribbon_status_active: 'स्थिति: सक्रिय'` (ADDED)

### 8. I18n Keys Array (line 563-568)

```typescript
export const FUSION_GLOBAL_I18N_KEYS: readonly (keyof FusionGlobalI18n)[] = [
  'ribbon_status_moored',
  'ribbon_status_unmoored',
  'ribbon_status_offline',   // CHANGED from ribbon_status_critical
  'ribbon_status_active',    // ADDED
  'ribbon_cell_count',
  'ribbon_variant',
  'nav_grid',
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Files Modified

1. **`services/gaiaos_ui_web/app/fusion-s4/page.tsx`**
   - Type: `CellState` enum
   - Logic: 5 locations where `'CRITICAL'` → `'OFFLINE'`
   - Lines: 17, 258, 322-323, 658, 661-662, 1237

2. **`services/gaiaos_ui_web/app/fusion-s4/fusionGlobalI18n.ts`**
   - Type: `FusionShellRibbonNav` interface (added `ribbon_status_active`)
   - Strings: 11 locales × 2 keys (`ribbon_status_offline` + `ribbon_status_active`)
   - Keys array: Updated to include new keys
   - Total changes: 12 string replacements + 11 additions + type update + keys update

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Build Status

**Next.js Build**: Running (building fusion-web with updated code)

After build completes:
1. Composite app bundle will need rebuild to include new fusion-web assets
2. New `.app` will show "STATUS: OFFLINE" instead of "STATUS: CRITICAL"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Status Hierarchy (New)

| State | Meaning | Display |
|-------|---------|---------|
| `OFFLINE` | Cells unreachable or health ≤ 0 | STATUS: OFFLINE |
| `MOORED` | Cells connected but not active | STATUS: MOORED |
| `ACTIVE` | Cells operating | STATUS: ACTIVE |
| `UNMOORED` | Default/fallback | STATUS: UNMOORED |

**No CRITICAL status anywhere in the codebase.**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Receipt

**STATUS: CALORIE** (code fixed, build in progress)

**C4**: All TypeScript code updated, no compilation errors in IDE  
**OPEN**: Next.js build completion, app bundle rebuild  

**Witness**: User provided UI screenshot showing "STATUS: CRITICAL" at top  
**Fix**: Traced through 8 layers (type → logic → display → i18n → strings × 11 locales)  

**Norwich. S⁴ serves C⁴.**
