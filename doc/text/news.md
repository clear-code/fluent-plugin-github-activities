# News

## 0.7.0: 2017-03-21

  * Use Fluentd v0.14 API
  * `pos_file` is obsoleted. Use storage instead.
  * Wait for processing remaining requests before shutdown

## 0.6.1: 2017-02-27

  * Add missing news entries.

## 0.6.0: 2017-02-27

  * Introduce secret parameter.
  * Support label feature.

## 0.5.0: 2015-06-06

 * Parallel crawling is land.
 * Reports related push event as a part of commit event.
 * Applies configured interval always.

## 0.4.0: 2015-06-02

 * Uses OAuth access token correctly.

## 0.3.0: 2015-06-02

 * Supports authentication with an access token for the OAuth.
   Instead, BASIC authentication is now obsolete.
 * Add `&github-activities-related-organization-icon` for forwarded records.
 * Report `push` evets even if they include commits already removed on the GitHub.

## 0.2.0: 2015-05-29

 * Fix inverted order of forwarded events: oldest event is now forwarded at first.

## 0.1.0: 2015-05-29

 * Initial release.
