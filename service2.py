from flask import Flask
from flask import request
import socket
import os
import sys
import requests

app = Flask(__name__)


@app.route('/service', methods=['GET', 'POST'])
def service():
	try:
		raise Exception("dad")
		app.logger.info(request.json)
		return socket.gethostbyname(socket.gethostname())
	except Exception as e:
		return '{"code": 500001, "msg": "sdfd"}',200,{'Status-Code': 500001}

@app.route('/test', methods=['GET', 'POST'])
def test():
	app.logger.info(request.json)
	return socket.gethostbyname(socket.gethostname())


if __name__ == "__main__":
    app.run(host='127.0.0.1', port=8080, debug=True)
