<?php

namespace Pim\Component\Connector\ArrayConverter\FlatToStandard\Product;

use Pim\Component\Catalog\Repository\GroupTypeRepositoryInterface;
use Pim\Component\Connector\ArrayConverter\FlatToStandard\ConvertedField;
use Pim\Component\Connector\ArrayConverter\FlatToStandard\FieldConverterInterface;

/**
 * Converts a flat field to a structured one
 *
 * @author    Olivier Soulet <olivier.soulet@akeneo.com>
 * @copyright 2015 Akeneo SAS (http://www.akeneo.com)
 * @license   http://opensource.org/licenses/osl-3.0.php  Open Software License (OSL 3.0)
 */
class FieldConverter implements FieldConverterInterface
{
    /** @var AssociationColumnsResolver */
    protected $assocFieldResolver;

    /** @var FieldSplitter */
    protected $fieldSplitter;

    /** @var GroupTypeRepositoryInterface */
    protected $groupTypeRepository;

    /**
     * @param FieldSplitter                $fieldSplitter
     * @param AssociationColumnsResolver   $assocFieldResolver
     * @param GroupTypeRepositoryInterface $groupTypeRepository
     */
    public function __construct(
        FieldSplitter $fieldSplitter,
        AssociationColumnsResolver $assocFieldResolver,
        GroupTypeRepositoryInterface $groupTypeRepository
    ) {
        $this->assocFieldResolver = $assocFieldResolver;
        $this->fieldSplitter = $fieldSplitter;
        $this->groupTypeRepository = $groupTypeRepository;
    }

    /**
     * {@inheritdoc}
     */
    public function convert(string $fieldName, string $value): array
    {
        $associationFields = $this->assocFieldResolver->resolveAssociationColumns();

        if (in_array($fieldName, $associationFields)) {
            $value = $this->fieldSplitter->splitCollection($value);
            list($associationTypeCode, $associatedWith) = $this->fieldSplitter->splitFieldName($fieldName);

            return [new ConvertedField('associations', [$associationTypeCode => [$associatedWith => $value]])];
        } elseif (in_array($fieldName, ['categories'])) {
            $categories = $this->fieldSplitter->splitCollection($value);

            return [new ConvertedField($fieldName, $categories)];
        } elseif (in_array($fieldName, ['groups'])) {
            return $this->extractVariantGroup($value);
        } elseif ('enabled' === $fieldName) {
            return [new ConvertedField($fieldName, $value)];
        } elseif ('family' === $fieldName) {
            return [new ConvertedField($fieldName, $value)];
        }

        throw new \LogicException(sprintf('No converters found for attribute type "%s"', $fieldName));
    }

    /**
     * @param string $column
     *
     * @return bool
     */
    public function supportsColumn($column): bool
    {
        $associationFields = $this->assocFieldResolver->resolveAssociationColumns();

        $fields = array_merge(['categories', 'groups', 'enabled', 'family'], $associationFields);

        return in_array($column, $fields);
    }

    /**
     * Extract a variant group from column "groups"
     *
     * @param string $value
     *
     * @return array
     */
    protected function extractVariantGroup($value): array
    {
        $data = $variantGroups = [];
        $groups = $this->fieldSplitter->splitCollection($value);

        foreach ($groups as $group) {
            $isVariant = $this->groupTypeRepository->getTypeByGroup($group);
            if ('1' === $isVariant) {
                $variantGroups[] = $group;
                $data[] = new ConvertedField('variant_group', $group);
            } else {
                $data[] = new ConvertedField('groups', $group);
            }
        }

        if (1 < count($variantGroups)) {
            throw new \InvalidArgumentException(
                sprintf('The product cannot belong to many variant groups: %s', implode(', ', $data['variant_group']))
            );
        }

        return $data;
    }
}
