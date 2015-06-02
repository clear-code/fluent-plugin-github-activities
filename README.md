# fluent-plugin-github-activities

Provides ability to watch public activities on GitHub.
This crawls GitHub activities of specified users and forward each activity as a record.

## Supported activity types

 * Activities related to commits
   * `push`
   * `commit` (See also following notes)
   * `commit-comment`
 * Activities related to repositories
   * `fork`
   * `branch`
   * `tag`
 * Activities related to issues
   * `issue-open`
   * `issue-close`
   * `issue-reopen`
   * `issue-assign`
   * `issue-unassign`
   * `issue-label`
   * `issue-unlabel`
 * Activities related to pull requests
   * `pull-request`
   * `pull-request-merged`
   * `pull-request-cancelled`
   * `pull-request-reopen`
   * `pull-request-comment`

Forwarded message is same to an activity provided by GitHub.
See also [the API documentations of GitHub activity events](https://developer.github.com/v3/activity/events/).

Notes:

 * Because a "push" activity doesn't include full information of each commit, commits are separately forwarded [commits](https://developer.github.com/v3/git/commits/) as pseudo `commit` activities.
 * All forwarded records have an extra property `$github-activities-related-avatar`.
   It will be useful to get the URI of the avatar image easily, for both activity events and commits.
 * All forwarded records have an extra property `$github-activities-related-organization-icon`.
   It will be useful to get the URI of the logo image of the organization easily, for both activity events and commits.
 * Unsupported activities are also forwarded with their raw event type like `StatusEvent`.


## Configurations

~~~
<source>
  type github-activities

  # Authentication settings.
  # They are optional but strongly recommended to be configured,
  # because there is a rate limit: 60requests/hour by default.
  # By an authenticated crawler, you can crawl 5000requests/hour
  # (means about 80requests/minute).
  basic_username your-user-name-of-github
  basic_password your-password-of-github

  # Interval seconds for requests. This is `1` by default.
  interval 1

  # Path to a file to store timestamp of last crawled activity
  # for each user. If you don't specify this option, same records
  # can be forwarded after the fluentd is restarted.
  pos_file /tmp/github-activities.json

  # Base tag of forwarded records. It will be used as
  # <base_tag>.<activity type>, like: "github-activity.push",
  # "github-activity.StatusEvent", etc.
  base_tag github-activity.

  # The lisf of target users' account IDs on the GitHub to be crawled.
  users ashie,co-me,cosmo0920,hayamiz,hhatto,kenhys,kou
  # External list is also available.
  #users_list /path/to/list/of/users

  # Merged pull requests will provide push and commit activities,
  # so you possibly see same commits twice when a pull request by
  # a known user (in the list above) is merged by another known user.
  # To avoid such annoying duplicated records, they are ignored by
  # default. If you hope those records are also forwarded, set this
  # option `true` manually.
  #include_commits_from_pull_request true

  # Pull requests can include commits by unknown users (out of the
  # list above) and the crawler ignores such users' commits by default.
  # To include those commit activities, set this option `true` manually.
  #include_foreign_commits true
</source>
~~~
