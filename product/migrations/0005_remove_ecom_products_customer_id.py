# Generated by Django 4.1.7 on 2023-05-19 11:58

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('product', '0004_ecom_products_customer_id_and_more'),
    ]

    operations = [
        migrations.RemoveField(
            model_name='ecom_products',
            name='customer_id',
        ),
    ]
