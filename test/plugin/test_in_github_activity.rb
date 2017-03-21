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

    data(normal: "users.txt",
         comment: "users-comment.txt")
    test "users_list" do |(user_list_path)|
      config = config_element("ROOT", "", { "users_list" => fixture_path(user_list_path) })
      d = create_driver(config)
      plugin = d.instance
      assert_equal(["okkez", "cosmo0920"], plugin.users)
    end
  end

  sub_test_case "emit" do
    test "simple" do
      user_events_template = Addressable::Template.new("https://api.github.com/users/{user}/events/public")
      stub_request(:get, user_events_template)
        .to_return(body: File.open(fixture_path("piroor-events.json")), status: 200)
      commits_template = Addressable::Template.new("https://api.github.com/repos/{owner}/{project}/commits/{commit_hash}")
      stub_request(:get, commits_template)
        .to_return(body: File.open(fixture_path("commit.json")), status: 200)
      config = config_element("ROOT", "", { "users" => "piroor", "@log_level" => "trace" })
      d = create_driver(config)
      d.run(timeout: 1, expect_emits: 2)
      tag, _time, record = d.events[0]
      assert_equal("github-activity.commit", tag)
      assert_equal("8e90721ff5d89f52b5b3adf0b86db01f03dc5588", record["sha"])
      tag, _time, record = d.events[1]
      assert_equal("github-activity.push", tag)
      assert_equal("2823041920", record["id"])
    end
  end
end
