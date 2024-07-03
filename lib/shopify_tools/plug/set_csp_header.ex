defmodule ShopifyTools.Plug.SetCspHeader do
  @moduledoc """
  Adds Content-Security-Policy frame-ancestors response header to the provided `Plug.Conn` in order to securely
  load embedded application in the Shopify admin panel.

  Read more here: https://shopify.dev/apps/store/security/iframe-protection#embedded-apps
  """

  @spec set_frame_ancestors(conn :: Plug.Conn.t(), opts :: Plug.opts()) :: Plug.Conn.t() | none()
  def set_frame_ancestors(conn, _opts) do
    # TODO: case the app is not embedded https://github.com/Shopify/shopify-app-js/blob/main/packages/apps/shopify-app-express/src/middlewares/csp-headers.ts

    shop =
      Plug.Conn.get_session(conn, :shopify_session, nil)[:shop] ||
        conn.query_params |> Map.fetch!("shop")

    conn
    |> Plug.Conn.put_resp_header(
      "Content-Security-Policy",
      "frame-ancestors https://#{shop} https://admin.shopify.com"
    )
  end
end
