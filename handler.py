import json
import pyjokes


def handler(event, context):
    body = {
        pyjokes.get_joke()
    }
    response = {
        "statusCode": 200,
        "body": json.dumps(body)
    }
    return response