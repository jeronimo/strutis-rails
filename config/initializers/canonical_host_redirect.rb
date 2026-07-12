if Rails.env.production?
  require Rails.root.join('app/middleware/canonical_host_redirect')

  Rails.application.config.middleware.unshift CanonicalHostRedirect
end
