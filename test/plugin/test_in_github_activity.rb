require "fluent/plugin/in_github-activities"
require "fluent/test"
require "fluent/test/helpers"
require "fluent/test/driver/input"

class TestGithubActivitiesInput < Test::Unit::TestCase
  include Fluent::Test::Helpers

  setup do
    Fluent::Test.setup
  end

  def create_driver(conf)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::GithubActivitiesInput).configure(conf)
  end

  sub_test_case "configure" do
    test "empty" do
      d = create_driver(config_element)
      plugin = d.instance
      storage = plugin._storages["in-github-activities"].storage
      assert { storage.path.nil? }
      assert { !storage.persistent }
    end

    test "obsoleted pos_file" do
      conf = config_element("ROOT", "", { "pos_file" => "/tmp/pos_file.json" })
      assert_raise Fluent::ObsoletedParameterError do
        create_driver(conf)
      end
    end

    data("end with .json" => ["/tmp/test.json", "/tmp/test.json"],
         "end with .pos" => ["/tmp/test.pos", "/tmp/test.pos/worker0/storage.json"])
    test "persistent storage with path" do |(path, expected_path)|
      storage_conf = config_element(
        "storage",
        "in-github-activities",
        { "@type" => "local", "persistent" => true, "path" => path }
      )
      conf = config_element("ROOT", "", {}, [storage_conf])
      d = create_driver(conf)
      plugin = d.instance
      storage = plugin._storages["in-github-activities"].storage
      assert_equal(expected_path, storage.path)
      assert { storage.persistent }
    end

    data(single: ["piroor", ["piroor"]],
         multiple: ["okkez,cosmo0920", ["okkez", "cosmo0920"]])
    test "users" do |(users, expected_users)|
      config = config_element("ROOT", "", { "users" => users })
      d = create_driver(config)
      plugin = d.instance
      assert_equal(expected_users, plugin.users)
    end

    test "users_list" do
      config = config_element("ROOT", "", { "users_list" => fixture_path("users.txt") })
      d = create_driver(config)
      plugin = d.instance
      assert_equal(["okkez", "cosmo0920"], plugin.users)
    end
  end
end
