#!/usr/bin/env python
# -*- coding:UTF-8 -*-

from __future__ import unicode_literals
import os
import sys
import logging
import click

logger = logging.getLogger(__name__)
__version__ = '1.0'
__author__ = 'caiqyxyx'

click.disable_unicode_literals_warning = True
pgk_dir = os.path.dirname(os.path.abspath(__file__))


class State(object):
    ''' Maintain logging level'''

    def __init__(self, log_name='rk', level=logging.INFO):
        self.logger = logging.getLogger(log_name)
        self.logger.propagate = False
        stream = logging.StreamHandler()
        formatter = logging.Formatter("%(levelname)-7s %(message)s ")
        stream.setFormatter(formatter)
        self.logger.addHandler(stream)
        self.logger.setLevel(level)


def can_build_cluster(replicas, slaves_pre_master):
    try:
        if replicas < 3 * (slaves_pre_master + 1):
            return False
        else:
            return True
    except Exception:
        return False


def verbose_option(f):
    def callback(ctx, param, value):
        state = ctx.ensure_object(State)
        if value:
            state.logger.setLevel(logging.DEBUG)

    return click.option('-vb', '--verbose',
                        is_flag=True,
                        expose_value=False,
                        help='Enable verbose output.',
                        callback=callback)(f)


def quiet_option(f):
    def callback(ctx, param, value):
        state = ctx.ensure_object(State)
        if value:
            state.logger.setLevel(logging.ERROR)

    return click.option('-q', '--quiet',
                        is_flag=True,
                        expose_value=False,
                        help='Silence Warning.',
                        callback=callback)(f)


def common_option(f):
    f = verbose_option(f)
    f = quiet_option(f)
    return f


@click.group(context_settings={'help_option_names': ['-h', '--help']})
@click.version_option('{0} from {1} (Python {2})'.format(__version__, pgk_dir, sys.version[:3]), '-v', '--version')
@common_option
def cli():
    """
    Redis cluster in kubernetes helper.
    """


@cli.command(name="install", help="Install the redis cluster.")
@click.option('-r', '--replicas', type=int, prompt="replicas",
              help="the replicas of the redis cluster StatefulSet(sts-redis-cluster).")
@click.option('-s', '--slaves-pre-master', type=int, prompt="slaves-pre-master",
              help="the count of pre salves of one master.")
@click.option('-api', '--api-server', type=str, prompt="api-server-addr", help="Enter the api server addr")
@click.option('-p', '--port', type=int, prompt="redis-server-port", help="Redis server port")
@click.option('-host', '--hostnetwork', is_flag=True, help="Use hostnetwork or not.")
@click.option('-sc', '--storageclass', is_flag=True, help="Enter your storageclass name.(kubectl get storageclass)")
@click.option('-i', '--image', type=str, prompt='docker-image', help="Enter your redis docker image.")
@common_option
def install_command(replicas, slaves_pre_master, api_server, port, hostnetwork, storageclass, image):
    if not can_build_cluster(replicas, slaves_pre_master):
        click.secho(
            'Wrong arguments! replicas must be greater than equal to (slaves_pre_master+1)*3 ', fg='red')
        return False
    from command import install
    result = install.install(pgk_dir, json_format=True,
                             replicas=replicas,
                             slaves_pre_master=slaves_pre_master,
                             api_server=api_server,
                             port=port,
                             hostnetwork=hostnetwork,
                             storageclass=storageclass,
                             image=image)
    click.secho(result, fg='blue')


@cli.command(name="uninstall", help="Uninstall the redis cluster.")
@common_option
def uninstall_command():
    from command import uninstall
    result = uninstall.uninstall(json_format=True)
    click.secho(result, fg='blue')


@cli.command(name="scale",
             help="Scale the replicas of the sts-redis-cluster,then the redis cluster will detect this change.")
@click.option('-r', '--replicas', type=int, prompt="new-replicas",
              help="the new replicas of the redis cluster StatefulSet(sts-redis-cluster)")
@common_option
def scale_command(replicas):
    from command import scale
    result = scale.scale(replicas, json_format=True)
    click.secho(result, fg='blue')


@cli.command(name="check", help="Health check for the redis cluster!")
@common_option
def check_health_command():
    from command import healthcheck
    result = healthcheck.health_check()
    click.secho(result, fg='blue')


@cli.command(name='build', help='Build the docker image.')
@click.option('-t', '--tag', type=str,prompt='image tag', help="Enter you docker image(tag) name.")
@common_option
def build_command(tag):
    from command import build
    result = build.build(tag)
    click.secho(result, fg='blue')


if __name__ == '__main__':
    cli()
