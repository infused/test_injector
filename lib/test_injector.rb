# Copyright (c) 2006 Keith Morrison (keithm@infused.org)
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

module TestInjector
  
  def self.included(base)
    base.extend ClassMethods
  end
  
  def klass
    @klass ||= Module.const_get(self.class.to_s.gsub(/Test$/, ''))
  end
  
  # Get all descendants of an acts_as_tree node
  def all_descendants(tree_node, id_only = true)
    nodes = tree_node.children.each {|subnode| all_descendants(subnode)}.flatten
    return id_only ? nodes.collect {|node| node.id} : nodes
  end
  
  def method_name
    return $1 if /`(.*)'/.match(caller.first)
  end
  
  module ClassMethods
    
    def klass
      @klass ||= Module.const_get(self.to_s.gsub(/Test$/, ''))
    end
    
    def inject_activerecord_tests
      if klass.ancestors.include?(ActiveRecord::Base)
        inject_association_tests
        define_acts_as_versioned_test(klass) if klass.respond_to?(:acts_as_versioned) and klass.respond_to?(:versioned_table_name)
        define_optimistic_locking_test(klass) if klass.column_names.include?("lock_version") && ActiveRecord::Base.lock_optimistically == true
      end
    end
  
    def inject_association_tests
      ignore_associations = [:versions, :parent, :children]
      collectible_associations = [:has_many, :has_and_belongs_to_many]
      klass.reflect_on_all_associations.each do |association|
        unless ignore_associations.include?(association.name)
          define_fixture_test(association)
          if collectible_associations.include?(association.macro)
            define_collectible_association_test(association)
          else
            define_association_test(association)
          end
          define_dependent_association_test(association) if association.options[:dependent]
        end
      end
    end
    
    def define_collectible_association_test(association)
      association_name = association.options[:through] ? "#{association.name}_through_#{association.options[:through]}" : association.name
      define_method "test_#{association.macro}_#{association_name}" do
        record = klass.find(:first)
        assert_kind_of Array, record.send(association.name), "#{klass}##{association.name} expected an array of #{association.class_name}'s"
        assert_kind_of association.klass, record.send(association.name).first, 
          "#{klass}##{association.name}.first should have returned a #{association.class_name}. If the result is a NilClass, verify your fixtures."
      end
    end
  
    def define_association_test(association)
      define_method "test_#{association.macro}_#{association.name}" do
        record = klass.find(:first)
        assert_kind_of association.klass, record.send(association.name), 
          "#{klass}##{association.name} was expected to be a #{association.class_name}. If the result is a NilClass, verify your fixtures."
      end
    end
    
    def define_dependent_association_test(association)
      define_method "test_#{association.options[:dependent]}_dependent_#{association.name}" do
        msg = "Unexpected result when calling #{association.options[:dependent]} on dependent association :#{association.name}"
        record = klass.find(:first)
        dependent_ids = record.send(association.name).is_a?(Array) ? record.send(association.name).map {|r| r.id} : [record.send(association.name)]
        assert record.destroy
        case association.options[:dependent]
        when :destroy, :delete_all  
          dependent_ids.each {|r| assert_raises(ActiveRecord::RecordNotFound, msg) { association.klass.find(r) }}
        when :nullify
          dependent_ids.each {|r| assert_nil association.klass.find(r).send(association.primary_key_name), msg}
        end
      end
    end

    # This test will run for any ActiveRecord model.  For each association defined in the model being tested (belongs_to, has_many, etc),
    # the test checks to see if a fixture corresponding to the associated model is included in the fixture list.
    def define_fixture_test(association)
      define_method "test_fixture_defined_for_#{association.klass.table_name}" do
        [association.klass.table_name, association.options[:join_table]].compact.each do |table_name|
          assert fixture_table_names.include?(table_name), "No fixture is defined for :#{table_name}"
        end
      end
    end
  
    # This test will run for any ActiveRecord model that uses the acts_as_versioned plugin. Versioning may fail if the versioned table is 
    # not set up correctly.  Including this test insures that versioning is set up correctly and is working as expected.
    def define_acts_as_versioned_test(base)
      define_method "test_acts_as_versioned" do
        msg = "ActsAsVersioned is not working correctly. Check the configuration of the #{base.table_name} and #{base.versioned_table_name} tables."
        model = base.find(:first)
        original_version = model.version
        assert model.save
        assert model.reload
        assert_equal original_version + 1, model.version, msg
        assert_equal model.version, model.versions.size, msg
      end
    end
  
    # This test will run for any ActiveRecord model that has a lock_version column. Optimistic locking may fail if the lock_version 
    # column is set to "not null" or does not have a default value.  Including this test insures that the lock_version column is set
    # up correctly.
    def define_optimistic_locking_test(base)
      define_method "test_optimistic_locking" do
        msg = "Optimistic locking is not functioning on the #{base.table_name} table. Check configuration of the lock_version column."
        model1 = base.find(:first)
        model2 = base.find(:first)
        assert model1.save
        assert_raises(ActiveRecord::StaleObjectError, msg) { model2.save }
      end
    end
    
  end
  
end