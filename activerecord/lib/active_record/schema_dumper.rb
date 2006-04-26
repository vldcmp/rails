module ActiveRecord
  # This class is used to dump the database schema for some connection to some
  # output format (i.e., ActiveRecord::Schema).
  class SchemaDumper #:nodoc:
    private_class_method :new
    
    # A list of tables which should not be dumped to the schema. 
    # Acceptable values are strings as well as regexp.
    # This setting is only used if ActiveRecord::Base.schema_format == :ruby
    cattr_accessor :ignore_tables 
    @@ignore_tables = []

    def self.dump(connection=ActiveRecord::Base.connection, stream=STDOUT)
      new(connection).dump(stream)
      stream
    end

    def dump(stream)
      header(stream)
      tables(stream)
      trailer(stream)
      stream
    end

    private

      def initialize(connection)
        @connection = connection
        @types = @connection.native_database_types
        @info = @connection.select_one("SELECT * FROM schema_info") rescue nil
      end

      def header(stream)
        define_params = @info ? ":version => #{@info['version']}" : ""

        stream.puts <<HEADER
# This file is autogenerated. Instead of editing this file, please use the
# migrations feature of ActiveRecord to incrementally modify your database, and
# then regenerate this schema definition.

ActiveRecord::Schema.define(#{define_params}) do

HEADER
      end

      def trailer(stream)
        stream.puts "end"
      end

      def tables(stream)
        @connection.tables.sort.each do |tbl|
          next if ["schema_info", ignore_tables].flatten.any? do |ignored|
            case ignored
            when String: tbl == ignored
            when Regexp: tbl =~ ignored
            else
              raise StandardError, 'ActiveRecord::SchemaDumper.ignore_tables accepts an array of String and / or Regexp values.'
            end
          end 
          table(tbl, stream)
        end
      end

      def table(table, stream)
        columns = @connection.columns(table)
        begin
          tbl = StringIO.new

          if @connection.respond_to?(:pk_and_sequence_for)
            pk, pk_seq = @connection.pk_and_sequence_for(table)
          end
          pk ||= 'id'

          tbl.print "  create_table #{table.inspect}"
          if columns.detect { |c| c.name == pk }
            if pk != 'id'
              tbl.print %Q(, :primary_key => "#{pk}")
            end
          else
            tbl.print ", :id => false"
          end
          tbl.print ", :force => true"
          tbl.puts " do |t|"

          column_specs = columns.map do |column|
            raise StandardError, "Unknown type '#{column.sql_type}' for column '#{column.name}'" if @types[column.type].nil?
            next if column.name == pk
            spec = {}
            spec[:name]    = column.name.inspect
            spec[:type]    = column.type.inspect
            spec[:limit]   = column.limit.inspect if column.limit != @types[column.type][:limit] 
            spec[:default] = column.default.inspect if !column.default.nil?
            spec[:null]    = 'false' if !column.null
            (spec.keys - [:name, :type]).each{ |k| spec[k].insert(0, "#{k.inspect} => ")}
            spec
          end.compact
          keys = [:name, :type, :limit, :default, :null] & column_specs.map{ |spec| spec.keys }.inject([]){ |a,b| a | b }
          lengths = keys.map{ |key| column_specs.map{ |spec| spec[key] ? spec[key].length + 2 : 0 }.max }
          format_string = lengths.map{ |len| "%-#{len}s" }.join("")
          column_specs.each do |colspec|
            values = keys.zip(lengths).map{ |key, len| colspec.key?(key) ? colspec[key] + ", " : " " * len }
            tbl.print "    t.column "
            tbl.print((format_string % values).gsub(/,\s*$/, ''))
            tbl.puts
          end

          tbl.puts "  end"
          tbl.puts
          
          indexes(table, tbl)

          tbl.rewind
          stream.print tbl.read
        rescue => e
          stream.puts "# Could not dump table #{table.inspect} because of following #{e.class}"
          stream.puts "#   #{e.message}"
          stream.puts
        end
        
        stream
      end

      def indexes(table, stream)
        indexes = @connection.indexes(table)
        indexes.each do |index|
          stream.print "  add_index #{index.table.inspect}, #{index.columns.inspect}, :name => #{index.name.inspect}"
          stream.print ", :unique => true" if index.unique
          stream.puts
        end
        stream.puts unless indexes.empty?
      end
  end
end
