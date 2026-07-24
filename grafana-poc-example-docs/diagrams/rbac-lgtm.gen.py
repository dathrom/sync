#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generator jednego kanonicznego modelu RBAC/LGTM -> D2 + Excalidraw (parytet 1:1)."""
import json, random, os

random.seed(42)
OUT = "/Users/artur.prawdzik/repo/sync/grafana-poc-example-docs/diagrams"

# ---- paleta warstw (fill, stroke) -------------------------------------------
CLS = {
    'sources':    ('#F8CECC', '#B85450'),
    'collector':  ('#FFE6CC', '#D79B00'),
    'azure':      ('#DAE8FC', '#6C8EBF'),
    'backend':    ('#FDEBD0', '#B85450'),
    'tenant':     ('#FFF2CC', '#D6B656'),
    'org':        ('#D9D2E9', '#8E7CC3'),
    'datasource': ('#D0E0E3', '#45818E'),
    'folder':     ('#D5E8D4', '#82B366'),
    'dashboard':  ('#FCE5CD', '#E69138'),
    'team':       ('#E1D5E7', '#9673A6'),
    'identity':   ('#E1D5E7', '#9673A6'),
    'network':    ('#F5F5F5', '#666666'),
    'note':       ('#FFFBEA', '#C9A227'),
    'optional':   ('#FFFFFF', '#999999'),
}
ZONE_STROKE = {  # obrys stref (kontenerów najwyższego poziomu)
    'zrodla': '#B85450', 'azure': '#6C8EBF', 'kolektory': '#D79B00',
    'backendy': '#B85450', 'tenanci': '#D6B656', 'grafana': '#8E7CC3',
    'entra': '#9673A6', 'mapping': '#666666', 'enterprise': '#999999',
    'security': '#C9A227', 'legenda': '#333333',
}

# =============================================================================
# MODEL: każdy diagram = lista stref (kontenerów) + lista krawędzi.
# Węzeł: (id, label, klasa, opcje{w, optional})
# Strefa: dict(id,title,layout('v'/'h'),children[Node|Strefa])
# Krawędź: (src, dst, label, private_bool, optional_bool)
# =============================================================================

def N(nid, label, cls, w=None, optional=False):
    return {'kind': 'node', 'id': nid, 'label': label, 'cls': cls, 'w': w, 'optional': optional}

def Z(zid, title, layout, children, cls=None):
    return {'kind': 'zone', 'id': zid, 'title': title, 'layout': layout,
            'children': children, 'cls': cls}

# ---------- wspólna LEGENDA (identyczna we wszystkich diagramach) -------------
def legenda():
    return Z('legenda', 'LEGENDA', 'v', [
        N('lg_sources', 'Źródła telemetrii', 'sources'),
        N('lg_collector', 'Kolektory na AKS (ustawiają X-Scope-OrgID)', 'collector'),
        N('lg_azure', 'Azure — usługi zarządzane', 'azure'),
        N('lg_backend', 'Backendy LGTM (ClusterIP, tylko wewnętrznie)', 'backend'),
        N('lg_tenant', 'Tenant — X-Scope-OrgID (partycja backendu)', 'tenant'),
        N('lg_org', 'Organizacja Grafany', 'org'),
        N('lg_ds', 'Data source (z przypiętym X-Scope-OrgID)', 'datasource'),
        N('lg_folder', 'Folder / podfolder', 'folder'),
        N('lg_dash', 'Dashboard', 'dashboard'),
        N('lg_team', 'Team = grupa Entra ID', 'team'),
        N('lg_note', 'Adnotacja / ustalenie ze spotkania', 'note'),
        N('lg_opt', 'Wariant Enterprise (team sync + DS perms / LBAC)', 'optional'),
        N('lg_solid', 'linia CIĄGŁA = łączność w klastrze / publiczna', 'note', w=360),
        N('lg_dash_l', 'linia PRZERYWANA = ścieżka PRYWATNA (Private Endpoint / ClusterIP)', 'note', w=360),
        N('lg_model', 'MODEL GŁÓWNY = OSS multi-org (org_mapping); Enterprise = wariant-adnotacja', 'note', w=360),
    ], cls='legenda')

# =============================================================================
# DIAGRAM 1 — Przepływ danych i tenanci
# =============================================================================
def diagram1():
    zones = [
        Z('zrodla', 'ŹRÓDŁA TELEMETRII', 'v', [
            N('src_azres', 'Logi zasobów Azure\n(Diagnostic Settings)', 'sources'),
            N('src_akslogs', 'Logi podów / kontenerów\n(AKS)', 'sources'),
            N('src_onpremlogs', 'Logi on-prem', 'sources'),
            N('src_aksmetrics', 'Metryki workloadów AKS\n(endpoint /metrics)', 'sources'),
            N('src_azmon', 'Metryki zasobów Azure\n(Azure Monitor)', 'sources'),
            N('src_onprommetrics', 'Exporter metryk on-prem', 'sources'),
            N('src_appA', 'Aplikacja A\n(OTel SDK — ślady)', 'sources'),
            N('src_appB', 'Aplikacja B\n(OTel SDK — ślady)', 'sources'),
        ]),
        Z('azure', 'AZURE', 'v', [
            N('eventhub', 'Azure Event Hub\n(bufor logów)', 'azure'),
        ]),
        Z('kolektory', 'KOLEKTORY (AKS) — USTAWIAJĄ X-Scope-OrgID', 'v', [
            N('vector', 'Vector\n(Event Hub → Loki)', 'collector'),
            N('azmon_exp', 'Azure Monitor exporter\n(→ Prometheus)', 'collector'),
            N('prometheus', 'Prometheus\n(scrape + remote_write)', 'collector'),
            N('otel', 'OTel Collector\n(OTLP + tail sampling)', 'collector'),
        ]),
        Z('backendy', 'BACKENDY LGTM (AKS, ClusterIP — TYLKO WEWNĘTRZNIE)', 'v', [
            N('loki', 'Loki (logi)', 'backend'),
            N('mimir', 'Mimir (metryki)', 'backend'),
            N('tempo', 'Tempo (ślady)', 'backend'),
        ]),
        Z('tenanci', 'TENANCI — X-Scope-OrgID (partycje backendów)', 'v', [
            N('t_ocms_dev', 'ra0395-ocms_klient-dev', 'tenant', w=250),
            N('t_ocms_uat', 'ra0395-ocms_klient-uat', 'tenant', w=250),
            N('t_olimps_dev', 'ra0766-olimps-dev', 'tenant', w=250),
            N('t_dingo_dev', 'ra0341-dingo-dev\n(opcjonalny 3. system)', 'tenant', w=250, optional=True),
            N('t_shared', 'shared\n(metryki dla wszystkich)', 'tenant', w=250),
        ]),
        Z('grafana', 'GRAFANA — ORGANIZACJE I DATA SOURCE\'Y', 'v', [
            Z('org_ocms', 'Org OCMS_KLIENT', 'v', [
                N('ds_loki_ocms_dev', 'Loki–OCMS-DEV\nX-Scope-OrgID: ra0395-ocms_klient-dev', 'datasource', w=300),
                N('ds_mimir_ocms_dev', 'Mimir–OCMS-DEV\nX-Scope-OrgID: ra0395-ocms_klient-dev', 'datasource', w=300),
                N('ds_tempo_ocms_dev', 'Tempo–OCMS-DEV\nX-Scope-OrgID: ra0395-ocms_klient-dev', 'datasource', w=300),
                N('ds_loki_ocms_uat', 'Loki–OCMS-UAT\nX-Scope-OrgID: ra0395-ocms_klient-uat', 'datasource', w=300),
            ], cls='org'),
            Z('org_olimps', 'Org OLIMPS', 'v', [
                N('ds_loki_olimps_dev', 'Loki–OLIMPS-DEV\nX-Scope-OrgID: ra0766-olimps-dev', 'datasource', w=300),
                N('ds_mimir_olimps_dev', 'Mimir–OLIMPS-DEV\nX-Scope-OrgID: ra0766-olimps-dev', 'datasource', w=300),
                N('ds_tempo_olimps_dev', 'Tempo–OLIMPS-DEV\nX-Scope-OrgID: ra0766-olimps-dev', 'datasource', w=300),
            ], cls='org'),
            Z('org_platform', 'Org Platform / Shared', 'v', [
                N('ds_mimir_shared', 'Mimir–shared\nX-Scope-OrgID: shared', 'datasource', w=300),
                N('ds_loki_cross', 'Loki–OCMS|OLIMPS (cross-tenant)\nX-Scope-OrgID:\nra0395-ocms_klient-dev|ra0766-olimps-dev', 'datasource', w=340),
            ], cls='org'),
        ]),
        Z('security', 'ADNOTACJE BEZPIECZEŃSTWA', 'v', [
            N('note_trust', 'GRANICA ZAUFANIA: backendy L/M/T ufają nagłówkowi\nX-Scope-OrgID → ClusterIP, nieosiągalne z sieci userów\n(dok. 16 §0)', 'note', w=360),
            N('note_wi', 'Workload Identity (UAMI + federated credential) — BRAK SEKRETÓW;\nPrivate Endpoint + prywatna strefa DNS do Event Hub / Azure Monitor', 'note', w=360),
            N('note_flow', 'Event Hub → Vector → Loki [L639];\nexporter → Prometheus → Mimir [L664];\naplikacje → OTel → Tempo [L699]', 'note', w=360),
            N('note_hdr', 'X-Scope-OrgID ustawiany przez kolektor, nienadpisywalny [L625];\nLoki bez row/index-level security [L810-813]', 'note', w=360),
        ]),
        legenda(),
    ]
    edges = [
        # źródła -> event hub / kolektory
        ('src_azres', 'eventhub', 'Diagnostic Settings → logi\nPrivate Endpoint + priv. DNS', True, False),
        ('eventhub', 'vector', 'odczyt AMQP, WI (brak sekretów)\nPrivate Endpoint [L639]', True, False),
        ('src_akslogs', 'vector', 'logi podów (w klastrze)', False, False),
        ('src_onpremlogs', 'vector', 'logi on-prem', False, False),
        ('src_aksmetrics', 'prometheus', 'scrape /metrics (pull)', False, False),
        ('src_azmon', 'azmon_exp', 'Azure Monitor API, WI\nprywatna', True, False),
        ('azmon_exp', 'prometheus', 'scrape exportera [L664]', False, False),
        ('src_onprommetrics', 'prometheus', 'scrape / remote', False, False),
        ('src_appA', 'otel', 'OTLP (gRPC)', False, False),
        ('src_appB', 'otel', 'OTLP (gRPC) [L699]', False, False),
        # kolektory -> backendy (zapis, X-Scope-OrgID)
        ('vector', 'loki', 'push HTTP, X-Scope-OrgID: <ra-system-env>\nnienadpisywalny [L625], w klastrze', False, False),
        ('prometheus', 'mimir', 'remote_write, WI, X-Scope-OrgID: <tenant> lub shared\nw klastrze', False, False),
        ('otel', 'tempo', 'OTLP, X-Scope-OrgID: <tenant>\nw klastrze', False, False),
        # backendy -> tenanci (partycjonowanie)
        ('loki', 'tenanci', 'partycje per X-Scope-OrgID\nbrak row/index-level security [L810-813]', False, False),
        ('mimir', 'tenanci', 'partycje per X-Scope-OrgID (+ shared) [L808]', False, False),
        ('tempo', 'tenanci', 'partycje per X-Scope-OrgID', False, False),
        # data source -> tenant (odczyt, ClusterIP prywatna)
        ('ds_loki_ocms_dev', 't_ocms_dev', 'LogQL, X-Scope-OrgID: ra0395-ocms_klient-dev\nClusterIP (prywatna)', True, False),
        ('ds_mimir_ocms_dev', 't_ocms_dev', 'PromQL, ClusterIP (prywatna)', True, False),
        ('ds_tempo_ocms_dev', 't_ocms_dev', 'TraceQL, ClusterIP (prywatna)', True, False),
        ('ds_loki_ocms_uat', 't_ocms_uat', 'LogQL, X-Scope-OrgID: ra0395-ocms_klient-uat\nClusterIP (prywatna)', True, False),
        ('ds_loki_olimps_dev', 't_olimps_dev', 'LogQL, X-Scope-OrgID: ra0766-olimps-dev\nClusterIP (prywatna)', True, False),
        ('ds_mimir_olimps_dev', 't_olimps_dev', 'PromQL, ClusterIP (prywatna)', True, False),
        ('ds_tempo_olimps_dev', 't_olimps_dev', 'TraceQL, ClusterIP (prywatna)', True, False),
        ('ds_mimir_shared', 't_shared', 'PromQL, X-Scope-OrgID: shared\n(metryki dla wszystkich) [L808,1302]', True, False),
        ('ds_loki_cross', 't_ocms_dev', 'LogQL, X-Scope-OrgID: ...ocms-dev|... (pipe)\ncross-tenant, ClusterIP', True, False),
        ('ds_loki_cross', 't_olimps_dev', 'LogQL, X-Scope-OrgID: ...|ra0766-olimps-dev\ncross-tenant, ClusterIP', True, False),
    ]
    return {'id': 'rbac-lgtm-1-dataflow', 'title': 'Diagram 1 — Przepływ danych i tenanci LGTM',
            'zones': zones, 'edges': edges}

# =============================================================================
# DIAGRAM 2 — Mapowanie Entra -> organizacje/teamy/foldery/uprawnienia
# =============================================================================
def diagram2():
    zones = [
        Z('entra', 'ENTRA ID — GRUPY (reprezentatywne z rbac_input.csv)', 'v', [
            N('g_ocms_reader', 'namespace_app-ocmsk-dev_..._reader\n(RA0395 / OCMS_KLIENT DEV)', 'identity', w=320),
            N('g_ocms_writer', 'namespace_app-ocmsk-dev_..._writer', 'identity', w=320),
            N('g_ocms_admin', 'self_prod_ra0395-dev_admin', 'identity', w=320),
            N('g_olimps_view', 'nonprd_view_...ra0766...dev-1\n(RA0766 / OLIMPS DEV)', 'identity', w=320),
            N('g_olimps_contrib', 'nonprd_contrybutor_...ra0766...dev-1', 'identity', w=320),
        ]),
        Z('mapping', 'MAPOWANIE TOŻSAMOŚCI', 'v', [
            N('oss_map', 'OSS: org_mapping\n[auth.azuread]\ngrupa → ORG + rola', 'collector', w=240),
            N('ent_sync', 'Enterprise: team sync\ngrupa → team (automat)', 'optional', w=240, optional=True),
        ]),
        Z('grafana', 'GRAFANA — ORGANIZACJE / TEAMY / FOLDERY', 'v', [
            Z('org_ocms', 'Org OCMS_KLIENT', 'v', [
                N('team_ocms_reader', 'team = ..._reader', 'team', w=250),
                N('team_ocms_writer', 'team = ..._writer', 'team', w=250),
                N('team_ocms_admin', 'team = self_prod_ra0395-dev_admin', 'team', w=250),
                Z('folder_ocms', 'Folder: RA0395 - OCMS_KLIENT', 'v', [
                    N('subf_ocms_dev', 'Podfolder: OCMS_KLIENT-DEV', 'folder', w=260),
                    N('subf_ocms_uat', 'Podfolder: OCMS_KLIENT-UAT', 'folder', w=260),
                ], cls='folder'),
                N('ds_loki_ocms_dev', 'Loki–OCMS-DEV\nX-Scope-OrgID: ra0395-ocms_klient-dev', 'datasource', w=300),
            ], cls='org'),
            Z('org_olimps', 'Org OLIMPS', 'v', [
                N('team_olimps_view', 'team = nonprd_view_...dev-1', 'team', w=250),
                N('team_olimps_contrib', 'team = nonprd_contrybutor_...dev-1', 'team', w=250),
                Z('folder_olimps', 'Folder: RA0766 - OLIMPS', 'v', [
                    N('subf_olimps_dev', 'Podfolder: OLIMPS-DEV', 'folder', w=260),
                ], cls='folder'),
                N('ds_loki_olimps_dev', 'Loki–OLIMPS-DEV\nX-Scope-OrgID: ra0766-olimps-dev', 'datasource', w=300),
            ], cls='org'),
        ]),
        Z('security', 'ADNOTACJE — OSS vs ENTERPRISE', 'v', [
            N('note_oss', 'OSS (MODEL GŁÓWNY): izolacja = brzeg ORGANIZACJI;\norg_mapping; rola zgrubna Viewer/Editor/Admin;\nDS powielany w każdej org (dok. 16 §1)', 'note', w=360),
            N('note_ent', 'ENTERPRISE (WARIANT): JEDNA org + team sync +\ndatasource permissions / LBAC; foldery per team;\ncustom roles (dok. 16 §2)', 'note', w=360),
            N('note_folders', 'Folder = (ra, system); podfolder = (ra, system, env);\nnadrzędny → View dla wszystkich teamów systemu;\npodfolder → View/Edit/Admin per wiersz CSV (folders.tf)', 'note', w=360),
        ]),
        legenda(),
    ]
    edges = [
        # grupa -> team (org_mapping OSS / team sync Enterprise)
        ('g_ocms_reader', 'team_ocms_reader', 'org_mapping → Org OCMS + rola\n(Enterprise: team sync)', False, False),
        ('g_ocms_writer', 'team_ocms_writer', 'org_mapping / team sync', False, False),
        ('g_ocms_admin', 'team_ocms_admin', 'org_mapping / team sync', False, False),
        ('g_olimps_view', 'team_olimps_view', 'org_mapping → Org OLIMPS', False, False),
        ('g_olimps_contrib', 'team_olimps_contrib', 'org_mapping / team sync', False, False),
        # mapowanie -> org
        ('oss_map', 'org_ocms', 'grupa → ORG + rola (Viewer/Editor/Admin)', False, False),
        ('ent_sync', 'org_ocms', 'grupa → team (jedna org)', False, True),
        # team -> folder nadrzędny (View)
        ('team_ocms_reader', 'folder_ocms', 'View (folder nadrzędny — cały system)', False, False),
        ('team_ocms_writer', 'folder_ocms', 'View (nadrzędny)', False, False),
        ('team_ocms_admin', 'folder_ocms', 'View (nadrzędny)', False, False),
        ('team_olimps_view', 'folder_olimps', 'View (nadrzędny)', False, False),
        ('team_olimps_contrib', 'folder_olimps', 'View (nadrzędny)', False, False),
        # team -> podfolder (View/Edit/Admin)
        ('team_ocms_reader', 'subf_ocms_dev', 'View', False, False),
        ('team_ocms_writer', 'subf_ocms_dev', 'Edit', False, False),
        ('team_ocms_admin', 'subf_ocms_dev', 'Admin', False, False),
        ('team_olimps_view', 'subf_olimps_dev', 'View', False, False),
        ('team_olimps_contrib', 'subf_olimps_dev', 'Edit', False, False),
        # team -> DS (Enterprise: datasource permissions) — wariant
        ('team_ocms_reader', 'ds_loki_ocms_dev', 'Query (Enterprise: DS permission)', False, True),
        ('team_ocms_writer', 'ds_loki_ocms_dev', 'Edit (Enterprise)', False, True),
        ('team_ocms_admin', 'ds_loki_ocms_dev', 'Admin (Enterprise)', False, True),
        ('team_olimps_view', 'ds_loki_olimps_dev', 'Query (Enterprise)', False, True),
        ('team_olimps_contrib', 'ds_loki_olimps_dev', 'Edit (Enterprise)', False, True),
    ]
    return {'id': 'rbac-lgtm-2-entra-rbac', 'title': 'Diagram 2 — Mapowanie Entra → org/team/folder/uprawnienia',
            'zones': zones, 'edges': edges}

# =============================================================================
# DIAGRAM 3 — Dashboard cross-tenant + OSS vs Enterprise
# =============================================================================
def diagram3():
    zones = [
        Z('entra', 'ENTRA ID', 'v', [
            N('g_platform', 'platform_observability\n(grupa Entra — centralny zespół)', 'identity', w=320),
        ]),
        Z('grafana', 'GRAFANA — Org Platform / Shared', 'v', [
            Z('org_platform', 'Org Platform / Shared', 'v', [
                N('team_platform', 'team platform_observability', 'team', w=260),
                Z('folder_platform', 'Folder: Platform / Cross-system', 'v', [
                    N('dash_cross', 'Dashboard: OCMS + OLIMPS\n(logi z 2 tenantów + metryki shared)', 'dashboard', w=300),
                ], cls='folder'),
                N('ds_loki_cross', 'Loki–OCMS|OLIMPS (cross-tenant)\nX-Scope-OrgID:\nra0395-ocms_klient-dev|ra0766-olimps-dev', 'datasource', w=340),
                N('ds_mimir_shared', 'Mimir–shared\nX-Scope-OrgID: shared', 'datasource', w=300),
            ], cls='org'),
        ]),
        Z('backendy', 'BACKENDY LGTM (AKS, ClusterIP)', 'v', [
            Z('loki', 'Loki (logi)', 'v', [
                N('t_ocms_dev', 'ra0395-ocms_klient-dev', 'tenant', w=250),
                N('t_olimps_dev', 'ra0766-olimps-dev', 'tenant', w=250),
            ], cls='backend'),
            Z('mimir', 'Mimir (metryki)', 'v', [
                N('t_shared', 'shared', 'tenant', w=250),
            ], cls='backend'),
        ]),
        Z('enterprise', 'WARIANT ENTERPRISE (adnotacja)', 'v', [
            N('ent_box', 'Zamiast multi-org + cross-tenant DS:\nJEDNA org + LBAC — 1 DS Loki,\nfiltr etykiet per team', 'optional', w=320, optional=True),
            N('ent_lbac', 'LBAC: reguły etykietowe per team\n(namespace / cluster); ⚠ fail-open\ngdy brak reguły (dok. 16 §2)', 'optional', w=320, optional=True),
        ]),
        Z('security', 'ADNOTACJE — CROSS-TENANT I KONCESJE', 'v', [
            N('note_cross', 'Cross-tenant query = feature backendu (OSS i Enterprise,\nlicense-free): X-Scope-OrgID: A|B, multi_tenant_queries_enabled\n(dok. 16 §3.1; L884, L893, L898)', 'note', w=380),
            N('note_shared', 'Koncesja: metryki „shared" widoczne dla wszystkich [L808, L1302];\nlogi = wiele data source\'ów, bo Loki bez row-level security [L810-813]', 'note', w=380),
            N('note_trust', 'Backendy ufają nagłówkowi → tylko ClusterIP / wewnętrznie;\nuser nie nadpisze X-Scope-OrgID przez Grafanę (backend przypina) [L625]\n(dok. 16 §0, §3.3)', 'note', w=380),
        ]),
        legenda(),
    ]
    edges = [
        ('g_platform', 'team_platform', 'org_mapping / team sync → Org Platform', False, False),
        ('team_platform', 'folder_platform', 'Admin / Edit (folder Platform)', False, False),
        ('team_platform', 'dash_cross', 'View (dashboard cross-tenant)', False, False),
        ('team_platform', 'ds_loki_cross', 'Query (Enterprise: DS permission)', False, True),
        ('dash_cross', 'ds_loki_cross', 'panel logów (2 tenanty)', False, False),
        ('dash_cross', 'ds_mimir_shared', 'panel metryk shared', False, False),
        ('ds_loki_cross', 't_ocms_dev', 'LogQL, X-Scope-OrgID: ...ocms-dev|... (pipe)\nmulti_tenant_queries_enabled, ClusterIP (prywatna)', True, False),
        ('ds_loki_cross', 't_olimps_dev', 'LogQL, X-Scope-OrgID: ...|ra0766-olimps-dev (pipe)\nClusterIP (prywatna)', True, False),
        ('ds_mimir_shared', 't_shared', 'PromQL, X-Scope-OrgID: shared\nmetryki dla wszystkich [L808,1302]', True, False),
        ('ent_box', 'ent_lbac', 'reguły LBAC', False, True),
    ]
    return {'id': 'rbac-lgtm-3-crosstenant', 'title': 'Diagram 3 — Dashboard cross-tenant + OSS vs Enterprise',
            'zones': zones, 'edges': edges}

DIAGRAMS = [diagram1(), diagram2(), diagram3()]

# =============================================================================
# RENDER D2
# =============================================================================
def d2_classes():
    out = ['classes: {']
    for name, (fill, stroke) in CLS.items():
        out.append(f'  {name}: {{')
        out.append(f'    style.fill: "{fill}"')
        out.append(f'    style.stroke: "{stroke}"')
        out.append('    style.stroke-width: 2')
        if name == 'optional':
            out.append('    style.stroke-dash: 4')
        out.append('  }')
    out.append('}')
    return '\n'.join(out)

def d2esc(s):
    return s.replace('"', '\\"').replace('\n', '\\n')

def d2_node(n, indent):
    pad = '  ' * indent
    lbl = d2esc(n['label'])
    line = f'{pad}{n["id"]}: "{lbl}" {{ class: {n["cls"]} }}'
    return line

def d2_zone(z, indent):
    pad = '  ' * indent
    out = []
    title = d2esc(z['title'])
    stroke = ZONE_STROKE.get(z['id'])
    out.append(f'{pad}{z["id"]}: "{title}" {{')
    if z.get('cls'):
        out.append(f'{pad}  class: {z["cls"]}')
    elif stroke:
        out.append(f'{pad}  style.stroke: "{stroke}"')
        out.append(f'{pad}  style.fill: "#FFFFFF"')
    for c in z['children']:
        if c['kind'] == 'node':
            out.append(d2_node(c, indent + 1))
        else:
            out.append(d2_zone(c, indent + 1))
    out.append(f'{pad}}}')
    return '\n'.join(out)

# indeks: id -> pełna ścieżka D2 (a.b.c)
def build_paths(zones):
    paths = {}
    def walk(node, prefix):
        p = f'{prefix}.{node["id"]}' if prefix else node['id']
        paths[node['id']] = p
        if node['kind'] == 'zone':
            for c in node['children']:
                walk(c, p)
    for z in zones:
        walk(z, '')
    return paths

def render_d2(diag):
    paths = build_paths(diag['zones'])
    out = []
    out.append(f'# {diag["title"]}')
    out.append('# Wygenerowane z kanonicznego modelu (rbac-lgtm.md) — parytet 1:1 z .excalidraw')
    out.append('')
    out.append('direction: right')
    out.append('')
    out.append(d2_classes())
    out.append('')
    for z in diag['zones']:
        out.append(d2_zone(z, 0))
        out.append('')
    out.append('# --- KRAWĘDZIE (protokół / auth / X-Scope-OrgID / prywatna?) ---')
    for src, dst, label, priv, opt in diag['edges']:
        sp, dp = paths[src], paths[dst]
        lbl = d2esc(label)
        styles = []
        if priv:
            styles.append('style.stroke-dash: 4')
        if opt:
            styles.append('style.stroke: "#999999"')
        if styles:
            out.append(f'{sp} -> {dp}: "{lbl}" {{ ' + '; '.join(styles) + ' }')
        else:
            out.append(f'{sp} -> {dp}: "{lbl}"')
    return '\n'.join(out) + '\n'

# =============================================================================
# RENDER EXCALIDRAW
# =============================================================================
PAD = 16
TITLE_H = 28
GAP = 16
CHAR_W = 7.0
LINE_H = 18
MIN_W = 200

def measure(node):
    """Ustala width/height (bottom-up) i zapisuje w node['w']/node['h']."""
    if node['kind'] == 'node':
        lines = node['label'].split('\n')
        maxlen = max(len(l) for l in lines)
        w = node.get('w') or max(MIN_W, int(maxlen * CHAR_W) + 24)
        node['w'] = w
        node['h'] = len(lines) * LINE_H + 20
        return
    # zone
    for c in node['children']:
        measure(c)
    if node['layout'] == 'v':
        w = max(c['w'] for c in node['children'])
        h = sum(c['h'] for c in node['children']) + GAP * (len(node['children']) - 1)
        node['w'] = w + 2 * PAD
        node['h'] = h + TITLE_H + PAD
    else:  # horizontal
        w = sum(c['w'] for c in node['children']) + GAP * (len(node['children']) - 1)
        h = max(c['h'] for c in node['children'])
        node['w'] = w + 2 * PAD
        node['h'] = h + TITLE_H + PAD

def place(node, x, y):
    """Przypisuje absolutne x,y (top-down)."""
    node['x'] = x
    node['y'] = y
    if node['kind'] == 'node':
        return
    cx = x + PAD
    cy = y + TITLE_H
    if node['layout'] == 'v':
        for c in node['children']:
            # wyśrodkuj w poziomie w kontenerze
            inner_w = node['w'] - 2 * PAD
            place(c, cx + (inner_w - c['w']) // 2, cy)
            cy += c['h'] + GAP
    else:
        for c in node['children']:
            place(c, cx, cy)
            cx += c['w'] + GAP

def collect(node, acc):
    acc.append(node)
    if node['kind'] == 'zone':
        for c in node['children']:
            collect(c, acc)

def rnd():
    return random.randint(1, 2**31 - 1)

def frac(i):
    return 'a' + str(i).zfill(4)

def ex_rect(node, idx, is_zone):
    fill, stroke = CLS.get(node.get('cls'), ('#FFFFFF', ZONE_STROKE.get(node['id'], '#333333')))
    if is_zone and not node.get('cls'):
        stroke = ZONE_STROKE.get(node['id'], '#333333')
        fill = '#FFFFFF'
    dashed = node.get('optional') or node.get('cls') == 'optional'
    return {
        'id': node['id'], 'type': 'rectangle',
        'x': node['x'], 'y': node['y'], 'width': node['w'], 'height': node['h'],
        'angle': 0, 'strokeColor': stroke,
        'backgroundColor': ('transparent' if is_zone else fill),
        'fillStyle': 'solid', 'strokeWidth': (3 if (is_zone and node['id'] == 'backendy') else 2),
        'strokeStyle': ('dashed' if dashed else 'solid'), 'roughness': 0, 'opacity': 100,
        'groupIds': [], 'frameId': None, 'roundness': {'type': 3},
        'seed': rnd(), 'versionNonce': rnd(), 'version': 1, 'isDeleted': False,
        'boundElements': [], 'updated': 1700000000000, 'link': None, 'locked': False,
        'index': frac(idx),
    }

def ex_label(node, idx, is_zone):
    """Tekst wewnątrz prostokąta (containerId)."""
    _, stroke = CLS.get(node.get('cls'), ('#FFFFFF', ZONE_STROKE.get(node['id'], '#333333')))
    text = node['title'] if is_zone else node['label']
    fs = 13 if is_zone else 13
    va = 'top' if is_zone else 'middle'
    return {
        'id': 't_' + node['id'], 'type': 'text',
        'x': node['x'] + 8, 'y': node['y'] + (6 if is_zone else node['h'] / 2 - 8),
        'width': node['w'] - 16, 'height': (LINE_H if is_zone else node['h'] - 12),
        'angle': 0, 'strokeColor': stroke, 'backgroundColor': 'transparent',
        'fillStyle': 'solid', 'strokeWidth': 1, 'strokeStyle': 'solid', 'roughness': 0,
        'opacity': 100, 'groupIds': [], 'frameId': None, 'roundness': None,
        'seed': rnd(), 'versionNonce': rnd(), 'version': 1, 'isDeleted': False,
        'boundElements': [], 'updated': 1700000000000, 'link': None, 'locked': False,
        'index': frac(idx),
        'text': text, 'fontSize': fs, 'fontFamily': 1,
        'textAlign': ('left' if is_zone else 'center'),
        'verticalAlign': va, 'containerId': node['id'],
        'originalText': text, 'lineHeight': 1.25, 'autoResize': False,
    }

def boundary_point(box, tx, ty):
    """Punkt na krawędzi prostokąta w kierunku (tx,ty)."""
    cx = box['x'] + box['w'] / 2
    cy = box['y'] + box['h'] / 2
    dx = tx - cx
    dy = ty - cy
    if dx == 0 and dy == 0:
        return cx, cy
    hw = box['w'] / 2
    hh = box['h'] / 2
    scale = min(hw / abs(dx) if dx != 0 else 1e9, hh / abs(dy) if dy != 0 else 1e9)
    return cx + dx * scale, cy + dy * scale

def render_excalidraw(diag):
    for z in diag['zones']:
        measure(z)
    # rozłóż strefy najwyższego poziomu w rzędzie (od lewej), top-align
    x = 100
    y = 100
    maxh = 0
    row_x = x
    for z in diag['zones']:
        place(z, row_x, y)
        row_x += z['w'] + 80
        maxh = max(maxh, z['h'])
    # zbierz wszystkie boksy
    boxes = []
    for z in diag['zones']:
        collect(z, boxes)
    box_by_id = {b['id']: b for b in boxes}
    zone_ids = set()
    def mark_zones(node):
        if node['kind'] == 'zone':
            zone_ids.add(node['id'])
            for c in node['children']:
                mark_zones(c)
    for z in diag['zones']:
        mark_zones(z)

    elements = []
    idx = 0
    # prostokąty + etykiety (strefy najpierw = pod spodem, potem węzły)
    ordered = [b for b in boxes if b['id'] in zone_ids] + [b for b in boxes if b['id'] not in zone_ids]
    rect_els = {}
    for b in ordered:
        is_zone = b['id'] in zone_ids
        r = ex_rect(b, idx, is_zone); idx += 1
        elements.append(r); rect_els[b['id']] = r
        lab = ex_label(b, idx, is_zone); idx += 1
        elements.append(lab)
        r['boundElements'].append({'type': 'text', 'id': lab['id']})
    # krawędzie
    for src, dst, label, priv, opt in diag['edges']:
        s = box_by_id[src]; d = box_by_id[dst]
        scx = s['x'] + s['w'] / 2; scy = s['y'] + s['h'] / 2
        dcx = d['x'] + d['w'] / 2; dcy = d['y'] + d['h'] / 2
        sx, sy = boundary_point(s, dcx, dcy)
        ex, ey = boundary_point(d, scx, scy)
        aid = f'e_{src}__{dst}'
        stroke = '#999999' if opt else '#495057'
        arrow = {
            'id': aid, 'type': 'arrow',
            'x': sx, 'y': sy, 'width': abs(ex - sx), 'height': abs(ey - sy),
            'angle': 0, 'strokeColor': stroke, 'backgroundColor': 'transparent',
            'fillStyle': 'solid', 'strokeWidth': 2,
            'strokeStyle': ('dashed' if (priv or opt) else 'solid'),
            'roughness': 0, 'opacity': 100, 'groupIds': [], 'frameId': None,
            'roundness': {'type': 2}, 'seed': rnd(), 'versionNonce': rnd(),
            'version': 1, 'isDeleted': False, 'boundElements': [], 'updated': 1700000000000,
            'link': None, 'locked': False, 'index': frac(idx),
            'points': [[0, 0], [ex - sx, ey - sy]], 'lastCommittedPoint': None,
            'startBinding': {'elementId': src, 'focus': 0.0, 'gap': 6},
            'endBinding': {'elementId': dst, 'focus': 0.0, 'gap': 6},
            'startArrowhead': None, 'endArrowhead': 'arrow',
        }
        idx += 1
        elements.append(arrow)
        rect_els[src]['boundElements'].append({'type': 'arrow', 'id': aid})
        rect_els[dst]['boundElements'].append({'type': 'arrow', 'id': aid})
        # etykieta krawędzi (label bound to arrow)
        lines = label.split('\n')
        maxlen = max(len(l) for l in lines)
        lw = int(maxlen * 6.2) + 10
        lh = len(lines) * 15
        mx = (sx + ex) / 2; my = (sy + ey) / 2
        ltxt = {
            'id': 'l_' + aid, 'type': 'text',
            'x': mx - lw / 2, 'y': my - lh / 2, 'width': lw, 'height': lh,
            'angle': 0, 'strokeColor': stroke, 'backgroundColor': '#ffffff',
            'fillStyle': 'solid', 'strokeWidth': 1, 'strokeStyle': 'solid', 'roughness': 0,
            'opacity': 100, 'groupIds': [], 'frameId': None, 'roundness': None,
            'seed': rnd(), 'versionNonce': rnd(), 'version': 1, 'isDeleted': False,
            'boundElements': [], 'updated': 1700000000000, 'link': None, 'locked': False,
            'index': frac(idx),
            'text': label, 'fontSize': 12, 'fontFamily': 1, 'textAlign': 'center',
            'verticalAlign': 'middle', 'containerId': aid,
            'originalText': label, 'lineHeight': 1.25, 'autoResize': False,
        }
        idx += 1
        elements.append(ltxt)
        arrow['boundElements'].append({'type': 'text', 'id': ltxt['id']})

    scene = {
        'type': 'excalidraw', 'version': 2, 'source': 'https://excalidraw.com',
        'elements': elements,
        'appState': {'viewBackgroundColor': '#ffffff', 'gridSize': None},
        'files': {},
    }
    return scene

# =============================================================================
# MAIN
# =============================================================================
for diag in DIAGRAMS:
    d2s = render_d2(diag)
    with open(os.path.join(OUT, diag['id'] + '.d2'), 'w') as f:
        f.write(d2s)
    scene = render_excalidraw(diag)
    with open(os.path.join(OUT, diag['id'] + '.excalidraw'), 'w') as f:
        json.dump(scene, f, ensure_ascii=False, indent=1)
    print(f"OK {diag['id']}: elementy excalidraw =", len(scene['elements']))

print("done")
