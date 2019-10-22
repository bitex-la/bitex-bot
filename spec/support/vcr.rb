require 'vcr'

VCR.configure do |c|
  c.allow_http_connections_when_no_cassette = false
  c.hook_into :webmock
  c.cassette_library_dir = 'spec/fixtures'
  c.configure_rspec_metadata!
end
