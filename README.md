# Dokku deployment step

Deploy your code to Dokku. This step requires that you deploy to a Dokku
deploy target. 

# Dependencies

These dependencies are required for this step. Make sure they are installed, and
available in `$PATH` before running this step:

- git
- mktemp
- curl
- ssh-keygen


# What's new

- Remove some changing of directories.
- Mark `source_dir` as deprecated. In a future version this will be replaced
  with `cwd`, currently they however are not compatible.

# Options

* `user` (optional) User used to create a new SSH key. Alternatively you can use
  the global environment variable `$DOKKU_USER`. Default is `dokku`.
* `host` (required) Host where Dokku instance is located. Alternatively you can use
  the global environment variable `$DOKKU_HOST`.
* `app-name` (required) The name of the app that you are deploying.
  Alternatively you can use `$DOKKU_APP_NAME`.
* `key-name` (required) Specify the name of the key that should be used for this
  deployment.
* `retry` (optional) When a deploy to Heroku fails, a new deploy is
  automatically performed after 5 seconds. If you want to disable this behavior,
  set `retry` to `false`.
* `run` (optional) Run a command on heroku after the code is deployed
  succesfully. This option can be used to migrate the database for example.
* `install-toolbelt` (optional). If set to 'true', the toolbelt will be
  installed. Note: specifying a run command will also install the toolbelt.
* `keep-repository` (optional) This will allow a user to keep the original
  history of the repository, speeding up deployment. **Important:** changes made
  during the build will not be deployed. Also keep in mind that deploying an
  already up to date repo will not result in an application restart. Use the
  `run` parameter to forcibly reload to achieve this. This feature is considered
  beta, expect issues. If you find one, please contact us.

# Example

``` yaml
deploy:
    steps:
        - dokku-deploy:
            host: my.dokku.io
            app-name: application-name
            key-name: MY_DEPLOY_KEY
```

# Using wercker SSH key pair

To push to Dokku we need to have an ssh key. You can generate a private/public key pair on wercker and
manually add the public key to Heroku.

- Generate a new key in wercker in the `Key management` section
  (`application` - `settings`).
- Copy the public key and add it on Dokku to the `SSH Keys section` section
  (`account`).
- In wercker edit the Dokku deploy target to which you would like to deploy,
  and add an environment variable:
    - Give the environment variable a name (remember this name, you will need it
      in the last step).
    - Select `SSH Key pair` as the type and select the key pair which you
      created earlier.
- In the `dokku-deploy` step in your `wercker.yml` add the `key-name` property
  with the value you used earlier:

```yaml
deploy:
    steps:
        - heroku-deploy:
            host: my.dokku.io 
            app-name: application-name
            key-name: MY_DEPLOY_KEY
```

In the above example the `MY_DEPLOY_KEY` should match the environment variable
name you used in wercker. Note: you should not prefix it with a dollar sign or
post fix it with `_PRIVATE` or `_PUBLIC`.

# License

The MIT License (MIT)

# Changelog

## 1.0.0

* Initial release, forked from heroku-deploy
