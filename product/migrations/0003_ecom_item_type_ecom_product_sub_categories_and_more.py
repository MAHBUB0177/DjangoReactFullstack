# Generated by Django 4.1.7 on 2023-05-19 10:34

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('product', '0002_remove_ecom_product_sub_categories_categories_id_and_more'),
    ]

    operations = [
        migrations.CreateModel(
            name='Ecom_item_type',
            fields=[
                ('categories_id', models.CharField(blank=True, max_length=20, primary_key=True, serialize=False)),
                ('categories_name', models.CharField(max_length=200)),
                ('app_user_id', models.CharField(blank=True, max_length=20, null=True)),
                ('app_data_time', models.DateTimeField(auto_now_add=True)),
            ],
        ),
        migrations.CreateModel(
            name='Ecom_Product_Sub_Categories',
            fields=[
                ('subcategories_id', models.CharField(blank=True, max_length=20, primary_key=True, serialize=False)),
                ('subcategories_name', models.CharField(max_length=200)),
                ('app_user_id', models.CharField(blank=True, max_length=20, null=True)),
                ('app_data_time', models.DateTimeField(auto_now_add=True)),
                ('categories_id', models.ForeignKey(blank=True, db_column='categories_id', null=True, on_delete=django.db.models.deletion.PROTECT, related_name='sub_categories_id', to='product.ecom_item_type')),
            ],
        ),
        migrations.CreateModel(
            name='Products_Unit',
            fields=[
                ('unit_id', models.CharField(blank=True, max_length=20, primary_key=True, serialize=False)),
                ('unit_name', models.CharField(max_length=200)),
                ('is_active', models.BooleanField(blank=True, default=True)),
                ('is_deleted', models.BooleanField(blank=True, default=False)),
                ('app_user_id', models.CharField(max_length=20)),
                ('app_data_time', models.DateTimeField(auto_now_add=True)),
            ],
        ),
        migrations.CreateModel(
            name='Ecom_Products',
            fields=[
                ('product_id', models.CharField(blank=True, max_length=20, primary_key=True, serialize=False)),
                ('product_name', models.CharField(max_length=200)),
                ('product_model', models.CharField(blank=True, max_length=200, null=True)),
                ('product_group', models.CharField(blank=True, max_length=200, null=True)),
                ('product_price', models.DecimalField(blank=True, decimal_places=2, default=0.0, max_digits=22, null=True)),
                ('discount_amount', models.DecimalField(blank=True, decimal_places=2, default=0.0, max_digits=22, null=True)),
                ('product_old_price', models.DecimalField(blank=True, decimal_places=2, default=0.0, max_digits=22, null=True)),
                ('product_feature', models.CharField(blank=True, max_length=500, null=True)),
                ('stock_limit', models.CharField(blank=True, max_length=500, null=True)),
                ('app_user_id', models.CharField(blank=True, max_length=20, null=True)),
                ('app_data_time', models.DateTimeField(auto_now_add=True)),
                ('category_id', models.ForeignKey(db_column='category_id', on_delete=django.db.models.deletion.PROTECT, related_name='product_category', to='product.ecom_item_type')),
                ('sub_category_id', models.ForeignKey(db_column='sub_category_id', on_delete=django.db.models.deletion.PROTECT, related_name='sub_product_category', to='product.ecom_product_sub_categories')),
                ('unit_id', models.ForeignKey(db_column='unit_id', on_delete=django.db.models.deletion.PROTECT, related_name='product_unit', to='product.products_unit')),
            ],
        ),
    ]
