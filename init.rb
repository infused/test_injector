if RAILS_ENV == 'test'  
  require 'test_injector'
  require 'test/unit'
  require 'tidy_functionals'

  Test::Unit::TestCase.class_eval do
    include TestInjector
  end
end
