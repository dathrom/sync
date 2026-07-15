# Konkretne wartości dla tego wdrożenia. Terraform wczytuje ten plik sam i nadpisuje
# nim domyślne wartości z variables.tf.

# Ustalone wartości, infra-plan rev3
# Locked values — infra-plan rev3
subscription_id     = "ac74f09f-f550-4aa6-b41f-0fbf419c85fd"
location            = "westeurope"
project             = "xyz-grafmon-lab"
owner               = "sebastian"
ttl                 = "destroy-after-demo"
test_user_object_id = "" # set to your AAD object ID if you want Grafana Viewer + Monitoring Reader grants
