locals {
  # The map of triggers from the `serviceContainer.triggers` configuration, filtered to keep only Pub/Sub triggers with
  # a valid (HTTP) endpoint.
  pubsub_triggers = local.enable_pubsub_triggers ? {
    for key, value in local.conf_triggers :
    key => value
    if try(value.type, null) == "event" && try(value.endpoint.type, null) == "http"
  } : {}
}

# Pub/Sub subscriptions for each Pub/Sub trigger defined in the configuration.
resource "google_pubsub_subscription" "triggers" {
  for_each = local.pubsub_triggers

  project = local.gcp_project_id
  # The subscriptions name is ensured to be unique by prefixing it with the service name.
  name  = "run-${local.service_name}-${each.key}"
  topic = local.pubsub_topic_ids[each.value.topic]

  ack_deadline_seconds = 600
  expiration_policy {
    ttl = ""
  }

  push_config {
    push_endpoint = "${google_cloud_run_service.service.status[0].url}${each.value.endpoint.path}"

    oidc_token {
      service_account_email = google_service_account.pubsub_trigger_invoker[0].email
    }
  }
}

# The service account used by Pub/Sub to invoke the Cloud Run service's triggers.
resource "google_service_account" "pubsub_trigger_invoker" {
  count = length(local.pubsub_triggers) > 0 ? 1 : 0

  project      = local.gcp_project_id
  account_id   = "${local.service_name}-pubsub"
  display_name = "${local.service_name} Pub/Sub triggers invoker"
  description  = "The service account used by Pub/Sub to invoke the Cloud Run ${local.service_name} service's triggers."
}

resource "google_cloud_run_service_iam_member" "pubsub_trigger_invoker" {
  count = length(local.pubsub_triggers) > 0 ? 1 : 0

  service  = google_cloud_run_service.service.name
  location = google_cloud_run_service.service.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.pubsub_trigger_invoker[0].email}"
}

# The Pub/Sub service itself must be able to create tokens for the "trigger invoker" service account that it uses to
# invoke the Cloud Run service's triggers.
resource "google_service_account_iam_member" "pubsub_agent_token_creator" {
  count = length(local.pubsub_triggers) > 0 ? 1 : 0

  service_account_id = google_service_account.pubsub_trigger_invoker[0].id
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
