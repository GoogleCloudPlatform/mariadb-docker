# <a name="about"></a>About

This image contains an installation of MariaDB 10.x.

For more information, see the
[Official Image Marketplace Page](https://console.cloud.google.com/marketplace/details/google/mariadb10).

Pull command (first install [gcloud](https://cloud.google.com/sdk/downloads)):

```shell
gcloud docker -- pull marketplace.gcr.io/google/mariadb10
```

Dockerfile for this image can be found [here](https://github.com/GoogleCloudPlatform/mariadb-docker/tree/master/10).

# <a name="table-of-contents"></a>Table of Contents
* [Using Kubernetes](#using-kubernetes)
  * [Running MariaDB server](#running-mariadb-server-kubernetes)
    * [Start a MariaDB instance](#start-a-mariadb-instance-kubernetes)
    * [Use a persistent data volume](#use-a-persistent-data-volume-kubernetes)
    * [Securely set up the server](#securely-set-up-the-server-kubernetes)
  * [Command line MariaDB client](#command-line-mariadb-client-kubernetes)
    * [Connect to a running MariaDB container](#connect-to-a-running-mariadb-container-kubernetes)
    * [Connect command line client to a remote MariaDB instance](#connect-command-line-client-to-a-remote-mariadb-instance-kubernetes)
  * [Configurations](#configurations-kubernetes)
    * [Using configuration volume](#using-configuration-volume-kubernetes)
    * [Using flags](#using-flags-kubernetes)
  * [Maintenance](#maintenance-kubernetes)
    * [Creating database dumps](#creating-database-dumps-kubernetes)
* [Using Docker](#using-docker)
  * [Running MariaDB server](#running-mariadb-server-docker)
    * [Start a MariaDB instance](#start-a-mariadb-instance-docker)
    * [Use a persistent data volume](#use-a-persistent-data-volume-docker)
    * [Securely set up the server](#securely-set-up-the-server-docker)
  * [Command line MariaDB client](#command-line-mariadb-client-docker)
    * [Connect to a running MariaDB container](#connect-to-a-running-mariadb-container-docker)
    * [Connect command line client to a remote MariaDB instance](#connect-command-line-client-to-a-remote-mariadb-instance-docker)
  * [Configurations](#configurations-docker)
    * [Using configuration volume](#using-configuration-volume-docker)
    * [Using flags](#using-flags-docker)
  * [Maintenance](#maintenance-docker)
    * [Creating database dumps](#creating-database-dumps-docker)
* [References](#references)
  * [Ports](#references-ports)
  * [Environment Variables](#references-environment-variables)
  * [Volumes](#references-volumes)

# <a name="using-kubernetes"></a>Using Kubernetes

Consult [Marketplace container documentation](https://cloud.google.com/marketplace/docs/marketplace-container)
for additional information about setting up your Kubernetes environment.

## <a name="running-mariadb-server-kubernetes"></a>Running MariaDB server

This section describes how to spin up a MariaDB service using this image.

### <a name="start-a-mariadb-instance-kubernetes"></a>Start a MariaDB instance

Copy the following content to `pod.yaml` file, and run `kubectl create -f pod.yaml`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: some-mariadb
  labels:
    name: some-mariadb
spec:
  containers:
    - image: marketplace.gcr.io/google/mariadb10
      name: mariadb
      env:
        - name: "MYSQL_ROOT_PASSWORD"
          value: "example-password"
```

Run the following to expose the port.
Depending on your cluster setup, this might expose your service to the
Internet with an external IP address. For more information, consult
[Kubernetes documentation](https://kubernetes.io/docs/concepts/services-networking/connect-applications-service/).

```shell
kubectl expose pod some-mariadb --name some-mariadb-3306 \
  --type LoadBalancer --port 3306 --protocol TCP
```

For information about how to retain your database across restarts, see [Use a persistent data volume](#use-a-persistent-data-volume-kubernetes).

See [Configurations](#configurations-kubernetes) for how to customize your MariaDB service instance.

Also see [Securely set up the server](#securely-set-up-the-server-kubernetes) for how to bootstrap the server with a more secure root password, without exposing it on the command line.

### <a name="use-a-persistent-data-volume-kubernetes"></a>Use a persistent data volume

We can store MariaDB data on a persistent volume. This way the database remains intact across restarts.

Copy the following content to `pod.yaml` file, and run `kubectl create -f pod.yaml`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: some-mariadb
  labels:
    name: some-mariadb
spec:
  containers:
    - image: marketplace.gcr.io/google/mariadb10
      name: mariadb
      env:
        - name: "MYSQL_ROOT_PASSWORD"
          value: "example-password"
      volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
          subPath: data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: data
---
# Request a persistent volume from the cluster using a Persistent Volume Claim.
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: data
  annotations:
    volume.alpha.kubernetes.io/storage-class: default
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
```

Run the following to expose the port.
Depending on your cluster setup, this might expose your service to the
Internet with an external IP address. For more information, consult
[Kubernetes documentation](https://kubernetes.io/docs/concepts/services-networking/connect-applications-service/).

```shell
kubectl expose pod some-mariadb --name some-mariadb-3306 \
  --type LoadBalancer --port 3306 --protocol TCP
```

Note that once the database directory is established, `MYSQL_ROOT_PASSWORD` will be ignored when the instance restarts.

### <a name="securely-set-up-the-server-kubernetes"></a>Securely set up the server

A recommended way to start up your MariaDB server is to have the root password generated on creation of the container. You can then log on and change this password.

Start the container with the environment variable `MYSQL_RANDOM_ROOT_PASSWORD` set to `yes`.

Copy the following content to `pod.yaml` file, and run `kubectl create -f pod.yaml`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: some-mariadb
  labels:
    name: some-mariadb
spec:
  containers:
    - image: marketplace.gcr.io/google/mariadb10
      name: mariadb
      env:
        - name: "MYSQL_RANDOM_ROOT_PASSWORD"
          value: "yes"
```

Run the following to expose the port.
Depending on your cluster setup, this might expose your service to the
Internet with an external IP address. For more information, consult
[Kubernetes documentation](https://kubernetes.io/docs/concepts/services-networking/connect-applications-service/).

```shell
kubectl expose pod some-mariadb --name some-mariadb-3306 \
  --type LoadBalancer --port 3306 --protocol TCP
```

You can then obtain the generated password by viewing the container log and look for the "GENERATED ROOT PASSWORD" line.

Open a shell to the container.

```shell
kubectl exec -it some-mariadb -- bash
```

Now log in with the generated password.

```
mysql -u root -p
```

Once logged in, you can change the root password.

```
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('New-Password');
```

Also see [Environment Variable reference](#references-environment-variables) for more information.

## <a name="command-line-mariadb-client-kubernetes"></a>Command line MariaDB client

This section describes how to use this image as a MariaDB client.

### <a name="connect-to-a-running-mariadb-container-kubernetes"></a>Connect to a running MariaDB container

You can run a MariaDB client directly within the container. Log on using the password for `root` user.

```shell
kubectl exec -it some-mariadb -- mysql -uroot -p
```

### <a name="connect-command-line-client-to-a-remote-mariadb-instance-kubernetes"></a>Connect command line client to a remote MariaDB instance

Assume that we have a MariaDB instance running at `some.mariadb.host` and we want to log on as `some-mariadb-user` when connecting.

```shell
kubectl run \
  some-mariadb-client \
  --image marketplace.gcr.io/google/mariadb10 \
  --rm --attach --restart=Never \
  -it \
  -- sh -c 'exec mysql -hsome.mariadb.host -usome-mariadb-user -p'
```

You will have to enter the password for `some-mariadb-user` to log on, even though there might not be a prompt to enter password due to limitations of `kubectl run --attach`.

## <a name="configurations-kubernetes"></a>Configurations

There are several ways to configure your MariaDB service instance.

### <a name="using-configuration-volume-kubernetes"></a>Using configuration volume

If `/my/custom/path/config-file.cnf` is the path and name of your custom configuration file, you can start your MariaDB container like this.

Create the following `configmap`:

```shell
kubectl create configmap config \
  --from-file=/my/custom/path/config-file.cnf
```

Copy the following content to `pod.yaml` file, and run `kubectl create -f pod.yaml`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: some-mariadb
  labels:
    name: some-mariadb
spec:
  containers:
    - image: marketplace.gcr.io/google/mariadb10
      name: mariadb
      env:
        - name: "MYSQL_ROOT_PASSWORD"
          value: "example-password"
      volumeMounts:
        - name: config
          mountPath: /etc/mysql/conf.d
  volumes:
    - name: config
      configMap:
        name: config
```

Run the following to expose the port.
Depending on your cluster setup, this might expose your service to the
Internet with an external IP address. For more information, consult
[Kubernetes documentation](https://kubernetes.io/docs/concepts/services-networking/connect-applications-service/).

```shell
kubectl expose pod some-mariadb --name some-mariadb-3306 \
  --type LoadBalancer --port 3306 --protocol TCP
```

See [Volume reference](#references-volumes) for more details.

### <a name="using-flags-kubernetes"></a>Using flags

You can specify option flags directly to `mysqld` when starting your instance. The following example sets the default encoding and collation for all tables to UTF-8.

Copy the following content to `pod.yaml` file, and run `kubectl create -f pod.yaml`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: some-mariadb
  labels:
    name: some-mariadb
spec:
  containers:
    - image: marketplace.gcr.io/google/mariadb10
      name: mariadb
      args:
        - --character-set-server=utf8mb4
        - --collation-server=utf8mb4_unicode_ci
      env:
        - name: "MYSQL_ROOT_PASSWORD"
          value: "example-password"
```

Run the following to expose the port.
Depending on your cluster setup, this might expose your service to the
Internet with an external IP address. For more information, consult
[Kubernetes documentation](https://kubernetes.io/docs/concepts/services-networking/connect-applications-service/).

```shell
kubectl expose pod some-mariadb --name some-mariadb-3306 \
  --type LoadBalancer --port 3306 --protocol TCP
```

You can also list all available options (several pages long).

```shell
kubectl run \
  some-mariadb-client \
  --image marketplace.gcr.io/google/mariadb10 \
  --rm --attach --restart=Never \
  -- --verbose --help
```

## <a name="maintenance-kubernetes"></a>Maintenance

### <a name="creating-database-dumps-kubernetes"></a>Creating database dumps

All databases can be dumped into a `/some/path/all-databases.sql` file on the host using the following command.

```shell
kubectl exec -it some-mariadb -- sh -c 'exec mysqldump --all-databases -uroot -p"$MYSQL_ROOT_PASSWORD"' > /some/path/all-databases.sql
```

If your container was not started with a `MYSQL_ROOT_PASSWORD` value, substitute `"$MYSQL_ROOT_PASSWORD"` with the password of the root user. Alternatively, you can use another pair of username as password for `-u` and `-p` arguments.

# <a name="using-docker"></a>Using Docker

Consult [Launcher container documentation](https://cloud.google.com/launcher/docs/launcher-container)
for additional information about setting up your Docker environment.

## <a name="running-mariadb-server-docker"></a>Running MariaDB server

This section describes how to spin up a MariaDB service using this image.

### <a name="start-a-mariadb-instance-docker"></a>Start a MariaDB instance

Use the following content for the `docker-compose.yml` file, then run `docker-compose up`.

```yaml
version: '2'
services:
  mariadb:
    container_name: some-mariadb
    image: marketplace.gcr.io/google/mariadb10
    environment:
      "MYSQL_ROOT_PASSWORD": "example-password"
    ports:
      - '3306:3306'
```

Or you can use `docker run` directly:

```shell
docker run \
  --name some-mariadb \
  -e "MYSQL_ROOT_PASSWORD=example-password" \
  -p 3306:3306 \
  -d \
  marketplace.gcr.io/google/mariadb10
```

MariaDB server is accessible on port 3306.

For information about how to retain your database across restarts, see [Use a persistent data volume](#use-a-persistent-data-volume-docker).

See [Configurations](#configurations-docker) for how to customize your MariaDB service instance.

Also see [Securely set up the server](#securely-set-up-the-server-docker) for how to bootstrap the server with a more secure root password, without exposing it on the command line.

### <a name="use-a-persistent-data-volume-docker"></a>Use a persistent data volume

We can store MariaDB data on a persistent volume. This way the database remains intact across restarts. Assume that `/my/persistent/dir/mariadb` is the persistent directory on the host.

Use the following content for the `docker-compose.yml` file, then run `docker-compose up`.

```yaml
version: '2'
services:
  mariadb:
    container_name: some-mariadb
    image: marketplace.gcr.io/google/mariadb10
    environment:
      "MYSQL_ROOT_PASSWORD": "example-password"
    ports:
      - '3306:3306'
    volumes:
      - /my/persistent/dir/mysql:/var/lib/mysql
```

Or you can use `docker run` directly:

```shell
docker run \
  --name some-mariadb \
  -e "MYSQL_ROOT_PASSWORD=example-password" \
  -p 3306:3306 \
  -v /my/persistent/dir/mysql:/var/lib/mysql \
  -d \
  marketplace.gcr.io/google/mariadb10
```

Note that once the database directory is established, `MYSQL_ROOT_PASSWORD` will be ignored when the instance restarts.

### <a name="securely-set-up-the-server-docker"></a>Securely set up the server

A recommended way to start up your MariaDB server is to have the root password generated on creation of the container. You can then log on and change this password.

Start the container with the environment variable `MYSQL_RANDOM_ROOT_PASSWORD` set to `yes`.

Use the following content for the `docker-compose.yml` file, then run `docker-compose up`.

```yaml
version: '2'
services:
  mariadb:
    container_name: some-mariadb
    image: marketplace.gcr.io/google/mariadb10
    environment:
      "MYSQL_RANDOM_ROOT_PASSWORD": "yes"
    ports:
      - '3306:3306'
```

Or you can use `docker run` directly:

```shell
docker run \
  --name some-mariadb \
  -e "MYSQL_RANDOM_ROOT_PASSWORD=yes" \
  -p 3306:3306 \
  -d \
  marketplace.gcr.io/google/mariadb10
```

You can then obtain the generated password by viewing the container log and look for the "GENERATED ROOT PASSWORD" line.

Open a shell to the container.

```shell
docker exec -it some-mariadb bash
```

Now log in with the generated password.

```
mysql -u root -p
```

Once logged in, you can change the root password.

```
SET PASSWORD FOR 'root'@'localhost' = PASSWORD('New-Password');
```

Also see [Environment Variable reference](#references-environment-variables) for more information.

## <a name="command-line-mariadb-client-docker"></a>Command line MariaDB client

This section describes how to use this image as a MariaDB client.

### <a name="connect-to-a-running-mariadb-container-docker"></a>Connect to a running MariaDB container

You can run a MariaDB client directly within the container. Log on using the password for `root` user.

```shell
docker exec -it some-mariadb mysql -uroot -p
```

### <a name="connect-command-line-client-to-a-remote-mariadb-instance-docker"></a>Connect command line client to a remote MariaDB instance

Assume that we have a MariaDB instance running at `some.mariadb.host` and we want to log on as `some-mariadb-user` when connecting.

```shell
docker run \
  --name some-mariadb-client \
  --rm \
  -it \
  marketplace.gcr.io/google/mariadb10 \
  sh -c 'exec mysql -hsome.mariadb.host -usome-mariadb-user -p'
```

## <a name="configurations-docker"></a>Configurations

There are several ways to configure your MariaDB service instance.

### <a name="using-configuration-volume-docker"></a>Using configuration volume

If `/my/custom/path/config-file.cnf` is the path and name of your custom configuration file, you can start your MariaDB container like this.

Use the following content for the `docker-compose.yml` file, then run `docker-compose up`.

```yaml
version: '2'
services:
  mariadb:
    container_name: some-mariadb
    image: marketplace.gcr.io/google/mariadb10
    environment:
      "MYSQL_ROOT_PASSWORD": "example-password"
    ports:
      - '3306:3306'
    volumes:
      - /my/custom/path/config-file.cnf:/etc/mysql/conf.d/config-file.cnf
```

Or you can use `docker run` directly:

```shell
docker run \
  --name some-mariadb \
  -e "MYSQL_ROOT_PASSWORD=example-password" \
  -p 3306:3306 \
  -v /my/custom/path/config-file.cnf:/etc/mysql/conf.d/config-file.cnf \
  -d \
  marketplace.gcr.io/google/mariadb10
```

See [Volume reference](#references-volumes) for more details.

### <a name="using-flags-docker"></a>Using flags

You can specify option flags directly to `mysqld` when starting your instance. The following example sets the default encoding and collation for all tables to UTF-8.

Use the following content for the `docker-compose.yml` file, then run `docker-compose up`.

```yaml
version: '2'
services:
  mariadb:
    container_name: some-mariadb
    image: marketplace.gcr.io/google/mariadb10
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
    environment:
      "MYSQL_ROOT_PASSWORD": "example-password"
    ports:
      - '3306:3306'
```

Or you can use `docker run` directly:

```shell
docker run \
  --name some-mariadb \
  -e "MYSQL_ROOT_PASSWORD=example-password" \
  -p 3306:3306 \
  -d \
  marketplace.gcr.io/google/mariadb10 \
  --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
```

You can also list all available options (several pages long).

```shell
docker run \
  --name some-mariadb-client \
  --rm \
  marketplace.gcr.io/google/mariadb10 \
  --verbose --help
```

## <a name="maintenance-docker"></a>Maintenance

### <a name="creating-database-dumps-docker"></a>Creating database dumps

All databases can be dumped into a `/some/path/all-databases.sql` file on the host using the following command.

```shell
docker exec -it some-mariadb sh -c 'exec mysqldump --all-databases -uroot -p"$MYSQL_ROOT_PASSWORD"' > /some/path/all-databases.sql
```

If your container was not started with a `MYSQL_ROOT_PASSWORD` value, substitute `"$MYSQL_ROOT_PASSWORD"` with the password of the root user. Alternatively, you can use another pair of username as password for `-u` and `-p` arguments.

# <a name="references"></a>References

## <a name="references-ports"></a>Ports

These are the ports exposed by the container image.

| **Port** | **Description** |
|:---------|:----------------|
| TCP 3306 | Standard MariaDB port. |

## <a name="references-environment-variables"></a>Environment Variables

These are the environment variables understood by the container image.

| **Variable** | **Description** |
|:-------------|:----------------|
| MYSQL_ROOT_PASSWORD | The password for `root` superuser. Required. <br><br> Instead of the explicit password string, a file path can also be used, in which case the content of the file is the password. |
| MYSQL_DATABASE | Optionally specifies the name of the database to be created at startup. |
| MYSQL_USER | Optionally specifies a new user to be created at startup. Must be used in conjunction with `MYSQL_PASSWORD`. Note that this user is in addition to the default `root` superuser. <br><br> If `MYSQL_DATABASE` is also specified, this user will be granted superuser permissions (i.e. `GRANT_ALL`) for that database. |
| MYSQL_PASSWORD | Used in conjunction with `MYSQL_USER` to specify the password. |
| MYSQL_RANDOM_ROOT_PASSWORD | If set to `yes`, a random initial password for `root` superuser will be generated. This password will be printed to stdout as `GENERATED ROOT PASSWORD: ...` |

## <a name="references-volumes"></a>Volumes

These are the filesystem paths used by the container image.

| **Path** | **Description** |
|:---------|:----------------|
| /var/lib/mysql | Stores the database files. |
| /etc/mysql/conf.d | Contains custom `.cnf` configuration files. <br><br> MariaDB startup configuration is specified in `/etc/mysql/my.cnf`, which in turn includes any `.cnf` files found in `/etc/mysql/conf.d` directory. |
