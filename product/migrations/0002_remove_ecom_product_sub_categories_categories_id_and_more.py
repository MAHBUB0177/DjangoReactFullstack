# Generated by Django 4.1.7 on 2023-05-19 10:31

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('product', '0001_initial'),
    ]

    operations = [
        migrations.RemoveField(
            model_name='ecom_product_sub_categories',
            name='categories_id',
        ),
        migrations.RemoveField(
            model_name='ecom_products',
            name='agent_id',
        ),
        migrations.RemoveField(
            model_name='ecom_products',
            name='category_id',
        ),
        migrations.RemoveField(
            model_name='ecom_products',
            name='sub_category_id',
        ),
        migrations.RemoveField(
            model_name='ecom_products',
            name='unit_id',
        ),
        migrations.DeleteModel(
            name='Ecom_item_type',
        ),
        migrations.DeleteModel(
            name='Ecom_Product_Sub_Categories',
        ),
        migrations.DeleteModel(
            name='Ecom_Products',
        ),
        migrations.DeleteModel(
            name='Products_Unit',
        ),
        migrations.DeleteModel(
            name='Sell_Agents',
        ),
    ]
