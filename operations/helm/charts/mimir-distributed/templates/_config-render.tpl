usage_stats:
  enabled: false
activity_tracker:
  filepath: /active-query-tracker/activity.log
enable_go_runtime_metrics: true
runtime_config:
  file: /var/{{ include "mimir.name" . }}/runtime.yaml
server:
  grpc_server_max_concurrent_streams: 1000
  grpc_server_max_connection_age: 2m
  grpc_server_max_connection_age_grace: 5m
  grpc_server_max_connection_idle: 1m
memberlist:
  abort_if_cluster_join_fails: false
  compression_enabled: false
  join_members:
  - dns+{{ include "mimir.fullname" . }}-gossip-ring.{{ .Release.Namespace }}.svc.{{ .Values.global.clusterDomain }}:{{ include "mimir.memberlistBindPort" . }}
distributor:
  remote_timeout: 5s
query_scheduler:
  max_outstanding_requests_per_tenant: 50
  # service_discovery_mode: ring # 在 frontend 和 querier配置 scheduler dns name
frontend_worker: # querier 与 frontend 通信
  grpc_client_config:
    max_send_msg_size: 419430400 # 400MiB
  {{- if .Values.query_scheduler.enabled }}
  scheduler_address: {{ template "mimir.fullname" . }}-query-scheduler-headless.{{ .Release.Namespace }}.svc:{{ include "mimir.serverGrpcListenPort" . }}
  {{- else }}
  frontend_address: {{ template "mimir.fullname" . }}-query-frontend-headless.{{ .Release.Namespace }}.svc:{{ include "mimir.serverGrpcListenPort" . }}
  {{- end }}
frontend:
  cache_results: true
  align_queries_with_step: false
  cache_unaligned_requests: true
  query_stats_enabled: true
  log_queries_longer_than: 10s
  log_query_request_headers: X-Scope-OrgID,user-agent
  parallelize_shardable_queries: true
  query_sharding_target_series_per_shard: 2500
  {{- if index .Values "results-cache" "enabled" }}
  results_cache:
    backend: memcached
    memcached:
      timeout: 500ms
      addresses: {{ include "mimir.resultsCacheAddress" . }}
      max_item_size: {{ mul (index .Values "results-cache").maxItemMemory 1024 1024 }}
  cache_results: true
  query_sharding_target_series_per_shard: 2500
  {{- end }}
  {{- if .Values.query_scheduler.enabled }}
  scheduler_address: {{ template "mimir.fullname" . }}-query-scheduler-headless.{{ .Release.Namespace }}.svc:{{ include "mimir.serverGrpcListenPort" . }}
  {{- end }}
querier:
  max_concurrent: 16
  lookback_delta: 58s
  query_store_after: 364d23h59m # 比 query_ingesters_within 少 1m，避免查询缺失
  prefer_streaming_chunks_from_ingesters: true
  prefer_streaming_chunks_from_store_gateways: true
  minimize_ingester_requests: true
ingester:
  ring:
    num_tokens: 512
    tokens_file_path: /data/tokens
    unregister_on_shutdown: false
    {{- if .Values.ingester.zoneAwareReplication.enabled }}
    zone_awareness_enabled: true
    {{- end }}
    replication_factor: 3
    unregister_on_shutdown: false # 避免ring hash变化导致时序量上涨
ingester_client:
  grpc_client_config:
    max_recv_msg_size: 104857600
    max_send_msg_size: 104857600
common:
  storage:
    backend: s3
    s3:
      access_key_id: mimir
      endpoint: s3coldstandby.dss.17usoft.com
      insecure: true
      region: us-east
      secret_access_key: mimir
compactor:
  compaction_interval: 30m
  deletion_delay: 2h
  max_closing_blocks_concurrency: 2
  max_opening_blocks_concurrency: 4
  symbols_flushers_concurrency: 4
  first_level_compaction_wait_period: 25m
  data_dir: "/data"
  sharding_ring:
    wait_stability_min_duration: 1m
blocks_storage:
  bucket_store:
    {{- if index .Values "chunks-cache" "enabled" }}
    chunks_cache:
      backend: memcached
      memcached:
        addresses: {{ include "mimir.chunksCacheAddress" . }}
        max_item_size: {{ mul (index .Values "chunks-cache").maxItemMemory 1024 1024 }}
        timeout: 450ms
        max_idle_connections: 150
    {{- end }}
    {{- if index .Values "index-cache" "enabled" }}
    index_cache:
      backend: memcached
      memcached:
        addresses: {{ include "mimir.indexCacheAddress" . }}
        max_item_size: {{ mul (index .Values "index-cache").maxItemMemory 1024 1024 }}
        timeout: 450ms
        max_idle_connections: 150
    {{- end }}
    {{- if index .Values "metadata-cache" "enabled" }}
    metadata_cache:
      backend: memcached
      memcached:
        addresses: {{ include "mimir.metadataCacheAddress" . }}
        max_item_size: {{ mul (index .Values "metadata-cache").maxItemMemory 1024 1024 }}
        max_idle_connections: 150
    {{- end }}
    sync_dir: /data/tsdb-sync
  backend: s3
  s3:
    bucket_name: mimir-blocks
  tsdb:
    dir: /data/tsdb
    retention_period: 87600h # 10 years
    close_idle_tsdb_timeout: 1440h # 60 days，必须大于 query_ingesters_within,否则会导致数据从 ingester 查不到
    ship_interval: 1m # 设置为0表示不开启shipper
    ship_concurrency: 10
    head_compaction_interval: 15m
    wal_replay_concurrency: 3
store_gateway:
  sharding_ring:
    wait_stability_min_duration: 1m
    {{- if .Values.store_gateway.zoneAwareReplication.enabled }}
    kvstore:
      prefix: multi-zone/
    {{- end }}
    tokens_file_path: /data/tokens
    unregister_on_shutdown: false
    {{- if .Values.store_gateway.zoneAwareReplication.enabled }}
    zone_awareness_enabled: true
    {{- end }}

# Default Limits
limits:
  # Distributor
  request_rate: 200
  request_burst_size: 300 # 300
  ingestion_rate: 100000
  ingestion_burst_size: 150000 # 150k
  accept_ha_samples: false
  max_label_name_length: 100
  max_label_value_length: 100
  service_overload_status_code_on_rate_limit_enabled: false

  # Ingester
  max_global_series_per_user: 1000000
  max_global_series_per_metric: 1000000 # 100w

  # Query-Frontend
  max_total_query_length: 60d # 查询最大时间跨度 end-start
  results_cache_ttl: 7d # 缓存 1 week
  results_cache_ttl_for_out_of_order_time_window: 10m
  cache_unaligned_requests: true
  align_queries_with_step: true

  # Querier
  max_query_parallelism: 240
  max_fetched_series_per_query: 10000000 # 1000w
  max_cache_freshness: 1m # ooo cache 10m 后会过期
  max_queriers_per_tenant: 10000
  query_ingesters_within: 365d