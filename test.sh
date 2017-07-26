#!/bin/bash
set -eux

# Prepare env vars
OS=${OS:="centos"}
OS_VERSION=${OS_VERSION:="7"}
PYTHON_VERSION=${PYTHON_VERSION:="2"}
IMAGE="$OS:$OS_VERSION"
# Pull fedora images from registry.fedoraproject.org
if [[ $OS == "fedora" ]]; then
  IMAGE="registry.fedoraproject.org/$IMAGE"
fi

CONTAINER_NAME="atomic-reactor-$OS-$OS_VERSION-py$PYTHON_VERSION"
RUN="docker exec -ti $CONTAINER_NAME"
if [[ $OS == "fedora" ]]; then
  if [[ $OS_VERSION == 25 && $PYTHON_VERSION == 2 ]]; then PIP_PKG="python-pip"; else PIP_PKG="python$PYTHON_VERSION-pip"; fi
  PIP="pip$PYTHON_VERSION"
  PKG="dnf"
  # F25 has outdated flatpak, don't run flatpak tests on it
  if [[ $OS_VERSION == 25 ]]; then PKG_EXTRA="dnf-plugins-core desktop-file-utils"; else PKG_EXTRA="dnf-plugins-core desktop-file-utils flatpak ostree"; fi
  BUILDDEP="dnf builddep"
  PYTHON="python$PYTHON_VERSION"
  PYTEST="py.test-$PYTHON_VERSION"
else
  PIP_PKG="python-pip"
  PIP="pip"
  PKG="yum"
  PKG_EXTRA="yum-utils epel-release git-core desktop-file-utils"
  BUILDDEP="yum-builddep"
  PYTHON="python"
  PYTEST="py.test"
fi
# Create container if needed
if [[ $(docker ps -q -f name=$CONTAINER_NAME | wc -l) -eq 0 ]]; then
  docker run --name $CONTAINER_NAME -d -v $PWD:$PWD -w $PWD -ti $IMAGE sleep infinity
fi

# Install dependencies
$RUN $PKG install -y $PKG_EXTRA
$RUN $BUILDDEP -y atomic-reactor.spec
if [[ $OS != "fedora" ]]; then
  # Install dependecies for test, as check is disabled for rhel
  $RUN yum install -y python-flexmock python-six \
                      python-docker-py python-backports-lzma \
                      python-responses \
                      python-requests python-requests-kerberos # OSBS dependencies
fi

# Install package
$RUN $PKG install -y $PIP_PKG
if [[ $PYTHON_VERSION == 3 && $OS_VERSION == rawhide ]]; then
  # https://fedoraproject.org/wiki/Changes/Making_sudo_pip_safe
  $RUN mkdir -p /usr/local/lib/python3.6/site-packages/
fi

# Install other dependencies for tests

# Install latest osbs-client by installing dependencies from the master branch
# and running pip install with '--no-deps' to avoid compilation
# This would also ensure all the deps are specified in the spec
$RUN git clone https://github.com/projectatomic/osbs-client /tmp/osbs-client
$RUN $BUILDDEP -y /tmp/osbs-client/osbs-client.spec
$RUN $PIP install --upgrade --no-deps --force-reinstall git+https://github.com/projectatomic/osbs-client

$RUN $PIP install --upgrade --no-deps --force-reinstall git+https://github.com/DBuildService/dockerfile-parse
if [[ $PYTHON_VERSION == 2* ]]; then
  $RUN $PIP install git+https://github.com/release-engineering/dockpulp
  $RUN $PIP install -r requirements-py2.txt
fi
$RUN $PIP install docker-squash
$RUN $PYTHON setup.py install

# Install packages for tests
$RUN $PIP install -r tests/requirements.txt

# Run tests
$RUN $PIP install pytest-cov
if [[ $OS != "fedora" ]]; then $RUN $PIP install -U pytest-cov; fi
$RUN $PYTEST -vv tests --cov atomic_reactor
