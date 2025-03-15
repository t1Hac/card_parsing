from confluent_kafka import Producer

def get_kafka_producer():
    conf = {'bootstrap.servers': 'host.docker.internal:9093'}
    return Producer(conf)