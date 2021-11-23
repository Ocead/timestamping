# ![](./res/ocead.svg) Ocead's Automated Timestamping

Automatically create trusted timestamps for your commits

This software allows you to add timestamps to your contributions to a Git repository via trusted third-party
timestamping services. As specified in [RFC 3161](https://www.rfc-editor.org/rfc/rfc3161.html), these timestamps may be
used to prove the existence of data at the time the timestamp was issued. This timestamp data may serve to derive proofs
of:

* Integrity of the data to be committed
* Ownership immediately *before* the commit
* Timeliness of the contributed work
* Authorship through self-disclosed copyright notices

All data used and generated by this software is stored in separate Git branches. You may choose freely to publish the
timestamps or keep them private as needed. This software runs entirely client-side.

## Requirements

* [Bash](https://www.gnu.org/software/bash/)
* [Curl](https://github.com/curl/curl)
* [Git](https://github.com/git/git)
* [OpenSSL](https://github.com/openssl/openssl)

## Installation

### Automatic

Run the [config.sh](config.sh) script with the path to the local repository you want to install automated timestamping
to:

```shell
./config.sh ~/path/to/repo
```

### Manual

1. Copy the contents of [hooks](hooks) directory into the `.git/hooks` directory of the target repository.
2. Set the options described in the [options](#options) section for at least the target repository.

> ℹ Note: if the script was installed into `.git/hooks` it is technically not part of the repository
> and will therefore **not** be versioned through commits **nor** sent to remotes through pushs.

> ⚠ Warning: If the repository you wish to install to already uses the `commit-msg` and `post-commit` hooks,
> make sure the scripts of this software are run **not** parallel to other hooked scripts that read or modify the
> repository.

## Functionality

This software uses OpenSSL to generate timestamps according to the "Internet X.509 Public Key Infrastructure Time-Stamp
Protocol" specified in [RFC 3161](https://www.rfc-editor.org/rfc/rfc3161.html).

### Creating timestamps

Timestamps of your commits are automtically created on calling [git-commit](https://git-scm.com/docs/git-commit).

On committing, this will happen behind the scenes:

1. Immediately before committing, a full diff (qualified for use with [git-apply](https://git-scm.com/docs/git-apply))
   of your staged changes / the staged state of the checked out branched is created.
2. This diff is placed into a separate signing branch, corresponding 1:1 to your normal non-signing branches.
3. The diff is then hashed, and a timestamping request for that hash is created in the signing branch for each time
   stamp authority you have configured.
4. These timestamping requests are sent to the timestamping servers and the responses are also be stored in the signing
   branch.
5. The diff, request and response files are then committed to the timestamping branch.
6. Afterwards, your staged contributions are committed to the non-signing branch.
7. This commit is then merged into its timestamping branch to relate the timestamp to it.
8. Lastly, the branch you committed to is checked out again.

### Retrieving timestamps

Timestamps are versioned in special signing branches, that match 1:1 to your regular branches. These branches have a
separate root, so you may withhold them when publishing your contributions as a Git repository.

To find the timestamp of the latest you created by committing changes, check out the appropriate signing branch
(provided default options) e.g.:

```shell
git checkout "sig/single"
```

to check out the timestamps created for commits on branch `single`.

To find the timestamp of a specific commit, refer to this diagram:

```
┊ ┊
o │ <- Merged timestamp/actual commit
│╲│
│ o <- Actual commit
│ │
o │ <- Timestamp commit
│ ┊
┊ ┴ <- Actual branch
┴   <- Signing branch
```

As the timestamps are created before the actual commits, they can not refer to the actual commit. Therefore, the actual
commit is merged into the signing branch afterwards, so that both the timestamp and actual commit are previous commits
of this new merged commit. However, to keep contributions and timestamps separate, the merged commit still only contains
the timestamp files.

You'll find the timestamp files from each configured TSA inside its respective configuration directory (provided default
options) e.g.

```
./
├ .diff <- Full diff of the staged files before committing
└ rfc3161/
  └ zeitstempel.dfn.de/
    ├ cacert.pem
    ├ request.tsq  <- Timestamp request
    ├ response.tsr <- Timestamp
    └ url
...
```

To verify the files against each other you may use these commands (provided default options):

* Show a trusted timestamp's contents:
  ```shell
  cd ./rfc3161/zeitstempel.dfn.de
  openssl ts -reply -in response.tsr -text
  ```

* Verify a timestamp against the request:
  ```shell
  cd ./rfc3161/zeitstempel.dfn.de
  openssl ts -verify -in response.tsr -queryfile request.tsq -CAfile cacert.pem
  ```

* Verify a timestamp against the diff:
  ```shell
  cd ./rfc3161/zeitstempel.dfn.de
  openssl ts -verify -in response.tsr -data ../../.diff -CAfile cacert.pem
  ```

## Configuring time stamp authorities (TSAs)

A time stamp authority is a trusted third party that signs data provided to it using asymmetric keys together with the
timestamp of receiving the data. With this, the TSA confirms that it was sent the signed data at the signed timestamp.
This software utilises the "Time-Stamp Protocol via HTTP" described
in [RFC 3161 Section 3.4](https://www.rfc-editor.org/rfc/rfc3161.html#section-3.4) for requesting timestamps.

### Configuring a new TSA

You can configure an arbitrary number of individual TSA for each repository. To configure a new timestamping server for
a repository where this software is installed to, do the following steps:

1. Check out the branch specified in `ts.branch.prefix` (`sig` by default).<br/>
   Example:
   ```shell
   git checkout sig
   ```

2. In there, navigate to the server specified in `ts.server.directory` (`rfc3161` by default) and create a new
   directory. The name of the directory specifies the domain of the timestamp server.<br/>
   ```shell
   cd rfc3161
   mkdir zeitstempel.dfn.de
   ```
   If the URL of the timestamp server is a resource on a domain, you may name this directory anything and place a file
   named `url` (can be changed via `ts.server.url`) containing the URL inside it instead.

3. Place the public keychain of the timestamp server inside the directory as `cacert.pem` (can be changed
   via `ts.server.certificate`)

The repository should look like this afterwards (provided default options):

```
./
└ rfc3161/
  └ zeitstempel.dfn.de/
    ├ cacert.pem
    └ url
...
```

> ℹ Note: You can find a list of free-to-use timestamping servers
> [here](https://gist.github.com/Manouchehri/fd754e402d98430243455713efada710).

### Updating a TSA configuration

You may want to change the configuration of a TSA if the URL to the server or the keychain of the server change. To do
so (provided default options):

1. Change the associated files/directory on branch `sig`.
2. Commit the changes to `sig`.

Upon committing to the `sig` branch, the timestamps for the changed TSA configurations will be updated for all branches
that already have a timestamp of the previous version of the TSA configuration.

### Deleting a TSA configuration

To delete a TSA configuration (provided default options):

1. Delete the associated directory in `rfc3161` on branch `sig`.
2. Commit deleting the directory to `sig`.

## Options

This software is controlled via [git-config](https://git-scm.com/docs/git-config). These options all occupy the `ts.`
namespace. They can be set via

```shell
git config <option> "<value>"
```

|Git config option|Description|Default value|
|---|---|---|
|`ts.branch.prefix`|The prefix used for branches created through and used by the automated timestamping.<br/>Will be appended with `-` for root branch and with `/<branch-name>` for each branch committed to.|`"sig"`|
|`ts.commit.prefix`|The prefix used for messages for commits containing timestamps.<br/>Will be appended with the commit message of the actual commit.|`"Timestamp for: "`|
|`ts.commit.options`|Options to apply to the `git commit` command for committing timestamps.|`""`|
|`ts.diff.notice`|Text added to the start of the timestamped diff files.|`"Written by $(git config --get user.name)"`|
|`ts.diff.file`|Name of the generated diff file|`".diff"`|
|`ts.diff.type`|Type of diff to be created.<br/>May either be:<br/>`"staged"` for diffs to HEAD, or <br/>`"full"` for diffs to the empty tree object.|`"staged"`|
|`ts.server.directory`|The directory containing the timestamp server configurations relative to the repositories root directory.|`"rfc3161"`|
|`ts.server.url`|Name of the file containing the url of the timestamp server.|`"url"`|
|`ts.server.certificate`|Name of the key chain file for a single timestamp server.|`"cacert.pem"`|
|`ts.request.file`|Name of the generated timestamp request file.|`"request.tsq"`|
|`ts.request.options`|Options for creating the timestamp request file through `openssl ts -query`.|`"-cert -sha256 -no_nonce"`|
|`ts.response.file`|Name of the received timestamp response file.|`"response.tsr"`|
|`ts.response.options`|Options for requesting the timestamp from the server through `curl`.|`""`|
|`ts.response.verify`|Whether the received timestamp should be verified against the diff and request file.<br/>May be `true` or `false`.|`"true"`|
|`ts.enabled`|Whether automated timestamping should be triggered on commits.<br/>May be `true` or `false`.|`"true"`|

> ⚠ Warning: Set the paths and filenames so that they don't interfere with what you plan to commit.

## Roadmap

* [x] Automatically creating RFC3161 timestamps
* [x] Multiple TSAs
* [x] Choice between cached and full diffs
* [x] Custom timestamp response options
* [x] Referencing actual commits in timestamping branches
* [x] Automatically redoing timestamps upon configuration changes
* [ ] TSA-specific/dynamic data providers
* [ ] Trusted timestamps after commits

## License

This software is released under the [Lesser GNU Public License v3](LICENSE).
