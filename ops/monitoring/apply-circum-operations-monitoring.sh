#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${1:-circum-2797c}"

ensure_uptime() {
  local name="$1" host="$2"
  if ! gcloud monitoring uptime list-configs --project "$PROJECT_ID" --format='value(displayName)' | grep -Fxq "$name"; then
    gcloud monitoring uptime create "$name" --project "$PROJECT_ID" --resource-type=uptime-url \
      --resource-labels="host=$host,project_id=$PROJECT_ID" --path=/ --protocol=https --period=5 --timeout=10 >/dev/null
  fi
}

ensure_metric() {
  local name="$1" description="$2" filter="$3"
  if ! gcloud logging metrics describe "$name" --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud logging metrics create "$name" --project "$PROJECT_ID" --description="$description" --log-filter="$filter" >/dev/null
  fi
}

ensure_policy() {
  local display_name="$1" metric_type="$2" threshold="$3" duration="$4"
  if gcloud monitoring policies list --project "$PROJECT_ID" --format='value(displayName)' | grep -Fxq "$display_name"; then
    return
  fi
  local policy
  policy="$(mktemp)"
  trap 'rm -f "$policy"' RETURN
  cat >"$policy" <<JSON
{
  "displayName": "$display_name",
  "combiner": "OR",
  "enabled": true,
  "documentation": {"content": "CIRCUM Operations Brain. Investigate the linked delivery/function evidence before retrying or overriding.", "mimeType": "text/markdown"},
  "conditions": [{
    "displayName": "$display_name",
    "conditionThreshold": {
      "filter": "metric.type=\"$metric_type\" resource.type=\"cloud_function\"",
      "comparison": "COMPARISON_GT",
      "thresholdValue": $threshold,
      "duration": "$duration",
      "aggregations": [{"alignmentPeriod": "300s", "perSeriesAligner": "ALIGN_SUM"}]
    }
  }]
}
JSON
  gcloud monitoring policies create --project "$PROJECT_ID" --policy-from-file="$policy" >/dev/null
}

ensure_uptime_policy() {
  local display_name="$1" check_id="$2"
  if gcloud monitoring policies list --project "$PROJECT_ID" --format='value(displayName)' | grep -Fxq "$display_name"; then return; fi
  local policy
  policy="$(mktemp)"
  trap 'rm -f "$policy"' RETURN
  cat >"$policy" <<JSON
{
  "displayName": "$display_name",
  "combiner": "OR",
  "enabled": true,
  "documentation": {"content": "CIRCUM Hosting is not passing its external HTTPS uptime check.", "mimeType": "text/markdown"},
  "conditions": [{"displayName": "$display_name", "conditionThreshold": {
    "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\" metric.label.check_id=\"$check_id\"",
    "comparison": "COMPARISON_LT", "thresholdValue": 1, "duration": "300s",
    "aggregations": [{"alignmentPeriod": "300s", "perSeriesAligner": "ALIGN_FRACTION_TRUE"}]
  }}]
}
JSON
  gcloud monitoring policies create --project "$PROJECT_ID" --policy-from-file="$policy" >/dev/null
}

ensure_latency_policy() {
  local display_name="CIRCUM Function Latency Risk"
  if gcloud monitoring policies list --project "$PROJECT_ID" --format='value(displayName)' | grep -Fxq "$display_name"; then return; fi
  local policy
  policy="$(mktemp)"
  trap 'rm -f "$policy"' RETURN
  cat >"$policy" <<JSON
{
  "displayName": "$display_name",
  "combiner": "OR",
  "enabled": true,
  "documentation": {"content": "The five-minute p99 Function execution time exceeds 45 seconds. Check timeout risk and downstream latency.", "mimeType": "text/markdown"},
  "conditions": [{"displayName": "$display_name", "conditionThreshold": {
    "filter": "metric.type=\"cloudfunctions.googleapis.com/function/execution_times\" resource.type=\"cloud_function\"",
    "comparison": "COMPARISON_GT", "thresholdValue": 45000000000, "duration": "300s",
    "aggregations": [{"alignmentPeriod": "300s", "perSeriesAligner": "ALIGN_PERCENTILE_99"}]
  }}]
}
JSON
  gcloud monitoring policies create --project "$PROJECT_ID" --policy-from-file="$policy" >/dev/null
}

ensure_uptime "CIRCUM Sender Hosting" "circum-app-2797c.web.app"
ensure_uptime "CIRCUM Rider Hosting" "circum-rider-2797c.web.app"
ensure_uptime "CIRCUM Admin Hosting" "circum-admin-2797c.web.app"

while IFS=$'\t' read -r check_id display_name; do
  [[ -n "$check_id" && -n "$display_name" ]] || continue
  ensure_uptime_policy "$display_name Unavailable" "$check_id"
done < <(gcloud monitoring uptime list-configs --project "$PROJECT_ID" --format='value(name.basename(),displayName)' | grep 'CIRCUM .* Hosting')

ensure_metric "circum_critical_function_errors" "Errors from critical payment, dispatch, lifecycle, communication and account Functions." \
  'resource.type=("cloud_function" OR "cloud_run_revision") severity>=ERROR (resource.labels.function_name=~".*(Payment|payment|Dispatch|dispatch|Delivery|delivery|Notification|notification|Message|message|Account|account).*" OR resource.labels.service_name=~".*(payment|dispatch|delivery|notification|message|account).*")'
ensure_metric "circum_payment_processing_errors" "Stripe webhook, checkout finalisation and payment processing errors." \
  'resource.type=("cloud_function" OR "cloud_run_revision") severity>=ERROR (textPayload=~"(?i)(stripe|payment|checkout|webhook|finali)" OR jsonPayload.message=~"(?i)(stripe|payment|checkout|webhook|finali)")'
ensure_metric "circum_notification_delivery_errors" "Notification persistence, push delivery and retry failures." \
  'resource.type=("cloud_function" OR "cloud_run_revision") severity>=ERROR (textPayload=~"(?i)(notification|push|fcm|message delivery)" OR jsonPayload.message=~"(?i)(notification|push|fcm|message delivery)")'
ensure_metric "circum_delivery_watchdog_errors" "Delivery lifecycle watchdog execution failures." \
  'resource.type=("cloud_function" OR "cloud_run_revision") severity>=ERROR (resource.labels.function_name="deliveryLifecycleWatchdog" OR resource.labels.service_name=~"deliverylifecyclewatchdog")'

ensure_policy "CIRCUM Critical Function Error Spike" "logging.googleapis.com/user/circum_critical_function_errors" 4 "300s"
ensure_policy "CIRCUM Payment Processing Failure" "logging.googleapis.com/user/circum_payment_processing_errors" 0 "0s"
ensure_policy "CIRCUM Notification Failure Growth" "logging.googleapis.com/user/circum_notification_delivery_errors" 9 "300s"
ensure_policy "CIRCUM Delivery Watchdog Failure" "logging.googleapis.com/user/circum_delivery_watchdog_errors" 0 "0s"
ensure_latency_policy

echo "CIRCUM monitoring configuration is present for project $PROJECT_ID."
