class CanonicalHostRedirect
  CANONICAL_HOST = 'strutis.ai'

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    return @app.call(env) if request.host == CANONICAL_HOST

    [ 301, { 'Location' => "https://#{CANONICAL_HOST}#{request.fullpath}" }, [] ]
  end
end
