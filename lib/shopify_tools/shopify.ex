defmodule ShopifyTools.Shopify do
  import Plug.Conn

  @moduledoc """
  You can use this module inside of another controller to handle initial iFrame load and shop installation

  Example:

  ```elixir
  defmodule MyAppWeb.AuthController do
    use MyAppWeb, :controller
    use ShopifyTools.AuthController

    # Thats it! Validation, installation are now handled for you :)
  end
  ```
  """
  @type shop :: %{access_token: String.t(), scope: String.t(), url: String.t()}
  @type shopify :: %{}
  @type t :: shopify()

  @doc """
  An callback called after the installation is completed, the shop is
  persisted in the database and webhooks are registered. By default, this function
  redirects the user to the app within their Shopify admin panel.

  ## Example

      @impl true
      def on_install(conn, shop, oauth_state) do
        # send yourself an e-mail about shop installation

        # follow default behaviour.
        super(conn, shop, oauth_state)
      end
  """
  @callback after_auth(conn :: Plug.Conn.t(), shopify(), session :: shop()) :: shopify()

  @optional_callbacks after_auth: 3

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour ShopifyTools.Shopify
      require Logger

      defstruct client_id: nil,
                client_secret: nil,
                endpoint: Keyword.fetch!(opts, :endpoint),
                app_url: Keyword.get(opts, :app_url, nil),
                api_version: Keyword.get(opts, :api_version, "2024-04"),
                is_embedded_app: Keyword.get(opts, :is_embedded_app, false),
                use_online_tokens: Keyword.get(opts, :use_online_tokens, false),
                scope: Keyword.get(opts, :scope, []),
                default_webhooks_opts:
                  Keyword.get(opts, :default_webhooks_opts,
                    callback_url: "/webhooks",
                    format: "json"
                  ),
                webhooks: Keyword.get(opts, :webhooks, [])

      @impl ShopifyTools.Shopify
      def after_auth(conn, _shopify, _) do
        conn
      end

      def shopify() do
        IO.inspect(Application.get_env(:protector, __MODULE__), label: "===== hereh: ")

        %__MODULE__{
          client_id: Application.get_env(:protector, __MODULE__)[:client_id],
          client_secret: Application.get_env(:protector, __MODULE__)[:client_secret]
        }
      end

      def register_webhooks(shopify \\ shopify(), session) do
        ShopifyTools.Webhooks.configure_webhooks(shopify, session)
      end

      @doc """
      get shopify session from session
      """
      def get_session(conn) do
        Plug.Conn.get_session(conn, :shopify_session, nil)
      end

      def fetch_shopify_session(conn, _opts) do
        shopify = shopify()

        case ShopifyTools.Plug.Session.create_session_token_context(conn, shopify) do
          {shop, claims, session_id, token} ->
            case Map.fetch(conn.private, :plug_session_fetch) do
              {:ok, :done} ->
                conn

              {:ok, fun} ->
                Logger.info("FETCHING SESSION #{session_id}")
                put_in(conn, [Access.key(:cookies), "_protector_key"], session_id) |> fun.()

              :error ->
                raise ArgumentError, "cannot fetch session without a configured session plug"
            end

          {:error, error} ->
            Logger.error("session token error #{error}")

            redirect_to_session_token_bounce_page(conn)
        end
      end

      @doc """
      plug for authenticate shopify shop
      1. validate session token
        1.1. case not valid - redirect to the same page to refresh the token
        1.2. case valid - go to section 2
      2. validate access token
        2.1. case not valid - exchange session token with access token and put in plug session
        2.2. case is valid - return conn
      """
      def authenticate(conn, _opts) do
        shopify = shopify()

        Logger.debug("authenticate plug")

        case ShopifyTools.Plug.Session.create_session_token_context(conn, shopify) do
          {shop, claims, session_id, token} ->
            Logger.debug("got session from token")
            # TODO: put session under session_id key?
            existing_session = Plug.Conn.get_session(conn, :shopify_session, nil)

            if(existing_session == nil) do
              Logger.info("No valid session found")
              Logger.info("Requesting offline access token")

              session =
                ShopifyTools.Plug.Session.exchange_token(shopify, token, shop.url,
                  is_online: false
                )

              Logger.debug("Put new session #{inspect(session)}")

              conn = Plug.Conn.put_session(conn, :shopify_session, session)
              conn = after_auth(conn, shopify, session)

              conn
            else
              Logger.debug("cannot get session from token")
              conn
            end

          {:error, error} ->
            Logger.error("session token error #{error}")

            redirect_to_session_token_bounce_page(conn)
        end
      end

      @doc """
      plug to verify webhook
      """
      def verify_webhook(conn, _opts) do
        shopify = shopify()

        case ShopifyTools.Hmac.validate(conn, shopify) do
          {:ok, check} ->
            conn
            |> Plug.Conn.assign(:shopify_webhook, %{
              api_version: check.api_version,
              shop: check.domain,
              topic: check.topic,
              webhook_id: check.webhook_id,
              payload: conn.body_params
            })

          _ ->
            Logger.info("HMAC does not match ")

            conn
            |> send_resp(401, "")
            |> halt()
        end
      end

      def render_bounce_page(conn, _params) do
        shopify = shopify()

        body = """
        <head>
            <meta name="shopify-api-key" content="#{shopify.client_id}" />
            <script src="https://cdn.shopify.com/shopifycloud/app-bridge.js"></script>
        </head>
        """

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, body)
        |> halt()
      end

      defp redirect_to_session_token_bounce_page(conn) do
        params = Map.drop(conn.query_params, ["id_token"])

        params =
          Map.put(params, "shopify-reload", "#{conn.request_path}?#{URI.encode_query(params)}")

        conn
        |> put_resp_header("location", "/auth/session-token-bounce?#{URI.encode_query(params)}")
        |> put_resp_content_type("text/html")
        |> send_resp(302, "")
        |> halt()
      end

      defoverridable after_auth: 3
    end
  end
end
