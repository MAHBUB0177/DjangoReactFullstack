# Generated by Django 4.1.7 on 2023-05-19 12:06

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('product', '0006_ecom_products_agen_name'),
    ]

    operations = [
        migrations.RemoveField(
            model_name='ecom_products',
            name='purchase_date',
        ),
    ]
