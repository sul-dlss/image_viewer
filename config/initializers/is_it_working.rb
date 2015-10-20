Rails.configuration.middleware.use(IsItWorking::Handler) do |h|
  h.check :directory, path: Settings.purl_resource.public_xml.sub(/%.*/, '')
end
