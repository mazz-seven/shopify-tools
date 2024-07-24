defmodule ShopifyTools.Webhooks do
  require Logger

  @type session :: %{access_token: String.t(), scope: String.t(), shop: String.t()}

  @doc """
  Check the webhooks set on the shop, then compare that to the required webhooks based on the current
  status of the shop.

  Returns a list of webhooks which were created.
  """
  def configure_webhooks(shopify, session) do
    Logger.info("configure webhooks topics #{inspect(shopify.webhooks)}")

    with {:ok, current_webhooks} <- get_current_webhooks(session, shopify) do
      current_webhook_topics = Enum.map(current_webhooks, &String.to_existing_atom(&1.node.topic))

      Logger.info(
        "All current webhook topics for #{session.shop}: #{Enum.join(current_webhook_topics, ", ")}"
      )

      current_webhook_topics = MapSet.new(current_webhook_topics)
      topics = MapSet.new(Keyword.keys(shopify.webhooks))

      # Make sure all the required topics are conifgured.
      subscribe_to_topics = MapSet.difference(topics, current_webhook_topics)

      Logger.info(
        "New webhook topics for #{session.shop}: #{Enum.join(subscribe_to_topics, ", ")}"
      )

      Enum.reduce(subscribe_to_topics, [], fn topic, acc ->
        Logger.info("Subscribing to topic #{topic}")

        case create_webhook(
               shopify,
               session,
               topic,
               Keyword.get(shopify.webhooks, topic, shopify.default_webhooks_opts)
             ) do
          {:ok, webhook} ->
            [webhook | acc]

          error ->
            Logger.info("Error subscribing to topic #{topic}: \n#{inspect(error)}")
            acc
        end
      end)
    end
  end

  @doc """
  Returns the current webhooks for a Shop from the Shopify API.

  Returns with `{:ok, webhooks}` on success. Can also return any
  non-200 level HTTPoison response, or a Jason decode error.
  """
  @spec get_current_webhooks(session :: session(), shopify :: any()) :: {:ok, list()} | any()
  def get_current_webhooks(session, shopify) do
    req =
      Req.new(
        url: "https://#{session.shop}/admin/api/#{shopify.api_version}/graphql.json",
        json: %{
          query: """
          query {
            webhookSubscriptions(first: 100) {
              edges {
                node {
                  id
                  topic
                  endpoint {
                    __typename
                    ... on WebhookHttpEndpoint {
                      callbackUrl
                    }
                  }
                }
              }
            }
          }
          """
        },
        headers: [
          "X-Shopify-Access-Token": session.access_token,
          "Content-Type": "application/json"
        ],
        decode_json: [keys: :atoms]
      )

    case Req.post(req) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        %{data: %{webhookSubscriptions: %{edges: webhooks}}} = body
        {:ok, webhooks}

      {:ok, %Req.Response{status: _status, body: body}} ->
        IO.inspect(body, label: "current_webhooks")

      error ->
        IO.inspect(error, label: "current_webhooks")
    end
  end

  def create_webhook(shopify, session, topic, webhook) do
    req =
      Req.new(
        url: "https://#{session.shop}/admin/api/#{shopify.api_version}/graphql.json",
        json: %{
          query: """
          mutation webhookSubscriptionCreate($topic: WebhookSubscriptionTopic!, $webhookSubscription: WebhookSubscriptionInput!) {
            webhookSubscriptionCreate(topic: $topic, webhookSubscription: $webhookSubscription) {
              webhookSubscription {
                id
                topic
                format
                endpoint {
                  __typename
                  ... on WebhookHttpEndpoint {
                    callbackUrl
                  }
                }
              }
            }
          }
          """,
          variables: %{
            topic: topic,
            webhookSubscription: %{
              callbackUrl:
                Path.join(shopify.endpoint.url(), Keyword.fetch!(webhook, :callback_url)),
              format: Keyword.get(webhook, :format, "JSON")
            }
          }
        },
        headers: [
          "X-Shopify-Access-Token": session.access_token,
          "Content-Type": "application/json"
        ],
        decode_json: [keys: :atoms]
      )

    case Req.post(req) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        %{data: %{webhookSubscriptionCreate: %{webhookSubscription: webhook}}} = body
        {:ok, webhook}

      {:ok, %Req.Response{status: _status, body: body}} ->
        IO.inspect(body, label: "create_webhook")

      error ->
        IO.inspect(error, label: "create_webhook")
    end
  end

  def delete_webhook(session, id) do
    Req.delete!(
      "https://#{session.shop}/admin/api/2024-01/webhooks/#{id}.json",
      headers: [
        "X-Shopify-Access-Token": session.access_token,
        "Content-Type": "application/json"
      ]
    )
  end
end
