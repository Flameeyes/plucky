module Plucky
  class Collection
    def initialize(collection)
      @collection = collection
    end

    def all(options={})
      query.update(options)
      [].tap do |docs|
        find(query.criteria, query.options).each { |doc| docs << doc }
      end
    end

    def first(options={})
      query.update(options)
      find_one(query.criteria, query.options)
    end

    def last(options={})
      query.update(options).reverse
      find_one(query.criteria, query.options)
    end

    def delete(options={})
      query.update(options)
      remove(query.criteria)
    end

    def count(options={})
      query.update(options)
      find(query.criteria, query.options).count
    end

    private
      def method_missing(method, *args, &block)
        @collection.send(method, *args, &block)
      end

      def query
        @query ||= Query.new
      end
  end
end