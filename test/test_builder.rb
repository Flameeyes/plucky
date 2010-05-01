require 'helper'

class BuilderTest < Test::Unit::TestCase
  include Plucky

  context "Converting to criteria" do
    %w{gt lt gte lte ne in nin mod all size exists}.each do |operator|
      next if operator == 'size' && RUBY_VERSION >= '1.9.1' # 1.9 defines Symbol#size

      should "convert #{operator} conditions" do
        Builder.new(:age.send(operator) => 21).criteria.should == {:age => {"$#{operator}" => 21}}
      end
    end

    should "work with simple criteria" do
      Builder.new(:foo => 'bar').criteria.should == {:foo => 'bar'}
      Builder.new(:foo => 'bar', :baz => 'wick').criteria.should == {:foo => 'bar', :baz => 'wick'}
    end

    should "work with multiple symbol operators on the same field" do
      Builder.new(:position.gt => 0, :position.lte => 10).criteria.should == {
        :position => {"$gt" => 0, "$lte" => 10}
      }
    end

    context "with id key" do
      should "convert to _id" do
        id = BSON::ObjectID.new
        Builder.new(:id => id).criteria.should == {:_id => id}
      end

      should "convert id with symbol operator to _id with modifier" do
        id = BSON::ObjectID.new
        Builder.new(:id.ne => id).criteria.should == {:_id => {'$ne' => id}}
      end
    end

    context "with time value" do
      should "convert to utc if not utc" do
        Builder.new(:created_at => Time.now).criteria[:created_at].utc?.should be(true)
      end

      should "leave utc alone" do
        Builder.new(:created_at => Time.now.utc).criteria[:created_at].utc?.should be(true)
      end
    end

    context "with array value" do
      should "default to $in" do
        Builder.new(:numbers => [1,2,3]).criteria.should == {:numbers => {'$in' => [1,2,3]}}
      end

      should "use existing modifier if present" do
        Builder.new(:numbers => {'$all' => [1,2,3]}).criteria.should == {:numbers => {'$all' => [1,2,3]}}
        Builder.new(:numbers => {'$any' => [1,2,3]}).criteria.should == {:numbers => {'$any' => [1,2,3]}}
      end

      should "work arbitrarily deep" do
        Builder.new(:foo => {:bar => [1,2,3]}).criteria.should == {:foo => {:bar => {'$in' => [1,2,3]}}}
        Builder.new(:foo => {:bar => {'$any' => [1,2,3]}}).criteria.should == {:foo => {:bar => {'$any' => [1,2,3]}}}
      end
    end

    context "with set value" do
      should "default to $in and convert to array" do
        Builder.new(:numbers => Set.new([1,2,3])).criteria.should == {:numbers => {'$in' => [1,2,3]}}
      end

      should "use existing modifier if present and convert to array" do
        Builder.new(:numbers => {'$all' => Set.new([1,2,3])}).criteria.should == {:numbers => {'$all' => [1,2,3]}}
        Builder.new(:numbers => {'$any' => Set.new([1,2,3])}).criteria.should == {:numbers => {'$any' => [1,2,3]}}
      end
    end
  end

  context "#filter" do
    should "update criteria" do
      Builder.new(:moo => 'cow').filter(:foo => 'bar').criteria.should == {:foo => 'bar', :moo => 'cow'}
    end

    should "get normalized" do
      Builder.new(:moo => 'cow').filter(:foo.in => ['bar']).criteria.should == {
        :moo => 'cow', :foo => {'$in' => ['bar']}
      }
    end
  end

  context "#where" do
    should "update criteria with $where statement" do
      Builder.new.where('this.writer_id = 1 || this.editor_id = 1').criteria.should == {
        '$where' => 'this.writer_id = 1 || this.editor_id = 1'
      }
    end
  end

  context "#fields" do
    should "update options (with array)" do
      Builder.new.fields([:foo, :bar, :baz]).options[:fields].should == [:foo, :bar, :baz]
    end

    should "update options (with hash)" do
      Builder.new.fields(:foo => 1, :bar => 0).options[:fields].should == {:foo => 1, :bar => 0}
    end
  end

  context "#limit" do
    should "set limit option" do
      Builder.new.limit(5).options[:limit].should == 5
    end

    should "override existing limit" do
      Builder.new(:limit => 5).limit(15).options[:limit].should == 15
    end
  end

  context "#skip" do
    should "set skip option" do
      Builder.new.skip(5).options[:skip].should == 5
    end

    should "override existing skip" do
      Builder.new(:skip => 5).skip(10).options[:skip].should == 10
    end
  end

  context "#update" do
    should "split and update criteria and options" do
      query = Builder.new(:foo => 'bar')
      query.update(:bar => 'baz', :skip => 5)
      query.criteria.should == {:foo => 'bar', :bar => 'baz'}
      query.options[:skip].should == 5
    end
  end

  context "order option" do
    should "single field with ascending direction" do
      sort = [['foo', 1]]
      Builder.new(:order => 'foo asc').options[:sort].should == sort
      Builder.new(:order => 'foo ASC').options[:sort].should == sort
    end

    should "single field with descending direction" do
      sort = [['foo', -1]]
      Builder.new(:order => 'foo desc').options[:sort].should == sort
      Builder.new(:order => 'foo DESC').options[:sort].should == sort
    end

    should "convert order operators to mongo sort" do
      query = Builder.new(:order => :foo.asc)
      query.options[:sort].should == [['foo', 1]]
      query.options[:order].should be_nil

      query = Builder.new(:order => :foo.desc)
      query.options[:sort].should == [['foo', -1]]
      query.options[:order].should be_nil
    end

    should "convert array of order operators to mongo sort" do
      Builder.new(:order => [:foo.asc, :bar.desc]).options[:sort].should == [['foo', 1], ['bar', -1]]
    end

    should "convert field without direction to ascending" do
      sort = [['foo', 1]]
      Builder.new(:order => 'foo').options[:sort].should == sort
    end

    should "convert multiple fields with directions" do
      sort = [['foo', -1], ['bar', 1], ['baz', -1]]
      Builder.new(:order => 'foo desc, bar asc, baz desc').options[:sort].should == sort
    end

    should "convert multiple fields with some missing directions" do
      sort = [['foo', -1], ['bar', 1], ['baz', 1]]
      Builder.new(:order => 'foo desc, bar, baz').options[:sort].should == sort
    end

    should "normalize id to _id" do
      Builder.new(:order => :id.asc).options[:sort].should == [['_id', 1]]
    end

    should "convert natural in order to proper" do
      sort = [['$natural', 1]]
      Builder.new(:order => '$natural asc').options[:sort].should == sort
      sort = [['$natural', -1]]
      Builder.new(:order => '$natural desc').options[:sort].should == sort
    end
  end

  context "sort option" do
    should "work for natural order ascending" do
      Builder.new(:sort => {'$natural' => 1}).options[:sort]['$natural'].should == 1
    end

    should "work for natural order descending" do
      Builder.new(:sort => {'$natural' => -1}).options[:sort]['$natural'].should == -1
    end

    should "should be used if both sort and order are present" do
      sort = [['$natural', 1]]
      Builder.new(:sort => sort, :order => 'foo asc').options[:sort].should == sort
    end
  end

  context "#reverse" do
    should "reverse the sort order" do
      query = Builder.new(:order => 'foo asc, bar desc')
      query.reverse.options[:sort].should == [['foo', -1], ['bar', 1]]
    end
  end

  context "skip option" do
    should "default to 0" do
      Builder.new({}).options[:skip].should == 0
    end

    should "use skip provided" do
      Builder.new(:skip => 2).options[:skip].should == 2
    end

    should "convert string to integer" do
      Builder.new(:skip => '2').options[:skip].should == 2
    end

    should "convert offset to skip" do
      Builder.new(:offset => 1).options[:skip].should == 1
    end
  end

  context "limit option" do
    should "default to 0" do
      Builder.new({}).options[:limit].should == 0
    end

    should "use limit provided" do
      Builder.new(:limit => 2).options[:limit].should == 2
    end

    should "convert string to integer" do
      Builder.new(:limit => '2').options[:limit].should == 2
    end
  end

  context "fields option" do
    should "default to nil" do
      Builder.new({}).options[:fields].should be(nil)
    end

    should "be converted to nil if empty string" do
      Builder.new(:fields => '').options[:fields].should be(nil)
    end

    should "be converted to nil if []" do
      Builder.new(:fields => []).options[:fields].should be(nil)
    end

    should "should work with array" do
      Builder.new({:fields => %w(a b)}).options[:fields].should == %w(a b)
    end

    should "convert comma separated list to array" do
      Builder.new({:fields => 'a, b'}).options[:fields].should == %w(a b)
    end

    should "also work as select" do
      Builder.new(:select => %w(a b)).options[:fields].should == %w(a b)
    end

    should "also work with select as array of symbols" do
      Builder.new(:select => [:a, :b]).options[:fields].should == [:a, :b]
    end
  end

  context "Criteria/option auto-detection" do
    should "know :conditions are criteria" do
      finder = Builder.new(:conditions => {:foo => 'bar'})
      finder.criteria.should == {:foo => 'bar'}
      finder.options.keys.should_not include(:conditions)
    end

    {
      :fields     => ['foo'],
      :sort       => 'foo',
      :hint       => '',
      :skip       => 0,
      :limit      => 0,
      :batch_size => 0,
      :timeout    => 0,
    }.each do |option, value|
      should "know #{option} is an option" do
        finder = Builder.new(option => value)
        finder.options[option].should == value
        finder.criteria.keys.should_not include(option)
      end
    end
    
    should "know select is an option and remove it from options" do
      finder = Builder.new(:select => 'foo')
      finder.options[:fields].should == ['foo']
      finder.criteria.keys.should_not include(:select)
      finder.options.keys.should_not  include(:select)
    end
    
    should "know order is an option and remove it from options" do
      finder = Builder.new(:order => 'foo')
      finder.options[:sort].should == [['foo', 1]]
      finder.criteria.keys.should_not include(:order)
      finder.options.keys.should_not  include(:order)
    end
    
    should "know offset is an option and remove it from options" do
      finder = Builder.new(:offset => 0)
      finder.options[:skip].should == 0
      finder.criteria.keys.should_not include(:offset)
      finder.options.keys.should_not  include(:offset)
    end

    should "work with full range of things" do
      query_options = Builder.new({
        :foo    => 'bar',
        :baz    => true,
        :sort   => [['foo', 1]],
        :fields => ['foo', 'baz'],
        :limit  => 10,
        :skip   => 10,
      })

      query_options.criteria.should == {
        :foo => 'bar',
        :baz => true,
      }

      query_options.options.should == {
        :sort   => [['foo', 1]],
        :fields => ['foo', 'baz'],
        :limit  => 10,
        :skip   => 10,
      }
    end
  end
end