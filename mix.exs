defmodule ShopifyTools.MixProject do
  use Mix.Project

  def project do
    [
      app: :shopify_tools,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:guardian, "~>2.3"},
      {:req, "~> 0.5.0"},
      {:plug, "~>1.16"}
    ]
  end
end
