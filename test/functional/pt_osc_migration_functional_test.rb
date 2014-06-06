require 'test_helper'

class PtOscMigrationFunctionalTest < ActiveRecord::TestCase
  class TestMigration < ActiveRecord::PtOscMigration; end

  context 'a migration connected to a pt-osc database' do
    setup do
      ActiveRecord::Base.establish_connection(test_spec)
      @migration = TestMigration.new
      @migration.instance_variable_set(:@connection, ActiveRecord::Base.connection)
    end

    context 'on an existing table with an existing column' do
      setup do
        @table_name = Faker::Lorem.word
        @column_name = Faker::Lorem.word
        @index_name = Faker::Lorem.words.join('_')
        @index_name_2 = "#{@index_name}_2"

        ActiveRecord::Base.connection.execute "DROP TABLE IF EXISTS `#{@table_name}`;"
        ActiveRecord::Base.connection.execute <<-SQL
          CREATE TABLE `#{@table_name}` (
            `#{@column_name}` varchar(255) DEFAULT NULL,
            KEY `#{@index_name}` (`#{@column_name}`)
          );
        SQL
      end

      teardown do
        ActiveRecord::Base.connection.execute "DROP TABLE IF EXISTS `#{@table_name}`;"
      end

      context 'a migration with only ALTER statements' do
        setup do
          TestMigration.class_eval <<-EVAL
            def change
              rename_table  :#{@table_name}, :#{Faker::Lorem.word}
              add_column    :#{@table_name}, :#{Faker::Lorem.word}, :integer
              change_column :#{@table_name}, :#{@column_name}, :varchar, default: 'newthing'
              rename_column :#{@table_name}, :#{@column_name}, :#{Faker::Lorem.word}
              remove_column :#{@table_name}, :#{@column_name}
              add_index     :#{@table_name}, :#{@column_name}, name: :#{@index_name_2}
              remove_index  :#{@table_name}, name: :#{@index_name}
            end
          EVAL
        end

        teardown do
          TestMigration.send(:remove_method, :change)
        end

        context 'ignoring schema lookups' do
          setup do
            # Kind of a hacky way to do this
            ignored_sql = ActiveRecord::SQLCounter.ignored_sql + [
              /^SHOW FULL FIELDS FROM/,
              /^SHOW COLUMNS FROM/,
              /^SHOW KEYS FROM/,
            ]
            ActiveRecord::SQLCounter.any_instance.stubs(:ignore).returns(ignored_sql)
          end

          teardown do
            ActiveRecord::SQLCounter.any_instance.unstub(:ignore)
          end

          context 'with suppressed output' do
            setup do
              @migration.stubs(:write)
              @migration.stubs(:announce)
            end

            teardown do
              @migration.unstub(:write, :announce)
            end

            should 'not execute any queries immediately' do
              assert_no_queries { @migration.change }
            end

            context 'with a working pt-online-schema-change' do
              setup do
                Kernel.expects(:system).with(regexp_matches(/^pt-online-schema-change/)).twice.returns(true)
              end

              teardown do
                Kernel.unstub(:system)
              end

              should 'not directly execute any queries when migrating' do
                assert_no_queries { @migration.migrate(:up) }
              end
            end
          end
        end
      end
    end
  end
end
