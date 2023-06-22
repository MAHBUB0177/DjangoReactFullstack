# Generated by Django 4.1.7 on 2023-04-03 16:17

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    initial = True

    dependencies = [
    ]

    operations = [
        migrations.CreateModel(
            name='Customer',
            fields=[
                ('id', models.CharField(blank=True, max_length=200, primary_key=True, serialize=False)),
                ('customer_name', models.CharField(blank=True, max_length=20, null=True)),
                ('phone_no', models.CharField(blank=True, max_length=20, null=True)),
                ('app_user_id', models.CharField(blank=True, max_length=20, null=True)),
            ],
        ),
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
            name='payment_bank',
            fields=[
                ('bank_id', models.CharField(blank=True, max_length=200, primary_key=True, serialize=False)),
                ('payment_bank', models.CharField(blank=True, max_length=20, null=True)),
                ('app_user_id', models.CharField(blank=True, max_length=20, null=True)),
                ('app_data_time', models.DateTimeField(auto_now_add=True)),
            ],
        ),
        migrations.CreateModel(
            name='payment_name',
            fields=[
                ('paymenttype_id', models.CharField(blank=True, max_length=200, primary_key=True, serialize=False)),
                ('payment_name', models.CharField(blank=True, max_length=20, null=True)),
                ('app_user_id', models.CharField(blank=True, max_length=20, null=True)),
                ('app_data_time', models.DateTimeField(auto_now_add=True)),
            ],
        ),
        migrations.CreateModel(
            name='Payment_type',
            fields=[
                ('payment_id', models.CharField(blank=True, max_length=200, primary_key=True, serialize=False)),
                ('payment_type', models.CharField(blank=True, max_length=200)),
                ('payment_amount', models.DecimalField(blank=True, decimal_places=2, default=0.0, max_digits=22, null=True)),
                ('check_bank', models.CharField(blank=True, max_length=200)),
                ('deposite_date', models.DateField(blank=True, null=True)),
                ('reference_no', models.CharField(blank=True, max_length=200)),
                ('bank_account', models.CharField(blank=True, max_length=200, null=True)),
                ('branch', models.CharField(blank=True, max_length=200)),
                ('app_user_id', models.CharField(blank=True, max_length=20, null=True)),
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
            name='Sell_Agents',
            fields=[
                ('agent_id', models.CharField(blank=True, max_length=200, primary_key=True, serialize=False)),
                ('agent_name', models.CharField(blank=True, max_length=20, null=True)),
                ('contact_no', models.CharField(blank=True, max_length=20, null=True)),
                ('address', models.CharField(blank=True, max_length=20, null=True)),
                ('email', models.CharField(blank=True, max_length=20, null=True)),
                ('gmail', models.CharField(blank=True, max_length=20, null=True)),
                ('app_user_id', models.CharField(blank=True, max_length=20, null=True)),
                ('app_data_time', models.DateTimeField(auto_now_add=True)),
            ],
        ),
        migrations.CreateModel(
            name='Ecom_Products',
            fields=[
                ('product_id', models.CharField(blank=True, max_length=20, primary_key=True, serialize=False)),
                ('product_name', models.CharField(max_length=200)),
                ('upload', models.ImageField(upload_to='uploads/')),
                ('product_model', models.CharField(blank=True, max_length=200, null=True)),
                ('product_group', models.CharField(blank=True, max_length=200, null=True)),
                ('product_price', models.DecimalField(blank=True, decimal_places=2, default=0.0, max_digits=22, null=True)),
                ('discount_amount', models.DecimalField(blank=True, decimal_places=2, default=0.0, max_digits=22, null=True)),
                ('product_old_price', models.DecimalField(blank=True, decimal_places=2, default=0.0, max_digits=22, null=True)),
                ('purchase_date', models.DateField(blank=True, null=True)),
                ('product_feature', models.CharField(blank=True, max_length=500, null=True)),
                ('stock_limit', models.CharField(blank=True, max_length=500, null=True)),
                ('app_user_id', models.CharField(blank=True, max_length=20, null=True)),
                ('app_data_time', models.DateTimeField(auto_now_add=True)),
                ('agent_id', models.ForeignKey(db_column='agent_id', on_delete=django.db.models.deletion.PROTECT, related_name='agents', to='product.sell_agents')),
                ('category_id', models.ForeignKey(db_column='category_id', on_delete=django.db.models.deletion.PROTECT, related_name='product_category', to='product.ecom_item_type')),
                ('sub_category_id', models.ForeignKey(db_column='sub_category_id', on_delete=django.db.models.deletion.PROTECT, related_name='sub_product_category', to='product.ecom_product_sub_categories')),
                ('unit_id', models.ForeignKey(db_column='unit_id', on_delete=django.db.models.deletion.PROTECT, related_name='product_unit', to='product.products_unit')),
            ],
        ),
    ]
