import csv
import random
from datetime import date, timedelta
 
random.seed(42)
hoje = date.today()
 
for transportadora_id in range(1, 5):
    nome_arquivo = f"transportadora_{transportadora_id}_{hoje.isoformat()}.csv"
    with open(nome_arquivo, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["pedido_id", "transportadora_id", "data_fatura", "custo_repassado"])
        for _ in range(30):
            pedido_id = random.randint(1, 500)
            custo = round(random.uniform(12.0, 85.0), 2)
            writer.writerow([pedido_id, transportadora_id, hoje.isoformat(), custo])
 
    print(f"Gerado: {nome_arquivo}")