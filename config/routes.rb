ImageViewer::Application.routes.draw do
  unless Rails.application.config.assets.compile
    get '/assets/purl_embed_jquery_plugin' => 'embed#purl_embed_jquery_plugin'
  end

  get ':id/embed' => 'embed#show'
  get ':id/embed-js' => 'embed#embed_js'
  get ':id/embed-html-json' => 'embed#embed_html_json'
end
