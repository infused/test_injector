if RAILS_ENV == 'test'  
  require 'test_injector'
  require 'test/unit'

  Test::Unit::TestCase.class_eval do
    include TestInjector
  end
end
